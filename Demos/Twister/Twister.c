#include "lwmf/lwmf.h"

#if SCREENWIDTH != 320
#error This effect expects SCREENWIDTH 320
#endif

#if SCREENHEIGHT != 256
#error This effect expects SCREENHEIGHT 256
#endif

#if NUMBEROFBITPLANES != 5
#error This effect expects NUMBEROFBITPLANES 5
#endif

#define COPPER_WORDS 160
#define COPPER_BYTES ((ULONG)COPPER_WORDS * sizeof(UWORD))
#define TWIST_TOP 96
#define TWIST_HEIGHT 64
#define TWIST_CENTER_X 160
#define TWIST_STRIP_WIDTH 1024
#define TWIST_STRIP_MASK 1023
#define TWIST_STRIP_BYTES (TWIST_STRIP_WIDTH >> 3)
#define TWIST_MIN_WIDTH 112
#define TWIST_MAX_WIDTH 240
#define EFFECT_SCREEN_STRIDE ((ULONG)BYTESPERROW * NUMBEROFBITPLANES)
#define EFFECT_SCREEN_BYTES (EFFECT_SCREEN_STRIDE * SCREENHEIGHT)
#define EFFECT_BPLMOD (EFFECT_SCREEN_STRIDE - BYTESPERROW)
#define BPLCON0_5BPL_LORES 0x5200
#define DEBUG_BLACK_ONLY 0

static volatile UWORD *const COP1LCH_REG = (volatile UWORD *const)0xDFF080;
static volatile UWORD *const COP1LCL_REG = (volatile UWORD *const)0xDFF082;
static volatile UWORD *const COPJMP1_REG = (volatile UWORD *const)0xDFF088;

static UWORD *Copper;
static UWORD *CopperBplPtrWords;
static UBYTE *TextStrip;
static WORD SinTab[256];
static UWORD WidthTab[256];
static WORD OffsetTab[256];

static void CopperPut(UWORD **cop, UWORD reg, UWORD val)
{
    *(*cop)++ = reg;
    *(*cop)++ = val;
}

static void StartCopper(UWORD *cop)
{
    ULONG p = (ULONG)cop;

    *COP1LCH_REG = p >> 16;
    *COP1LCL_REG = p & 0xFFFF;
    *COPJMP1_REG = 0;
}

static void SetCopperScreen(UBYTE *screen)
{
    UWORD *cop = CopperBplPtrWords;
    ULONG ptr;

    for (UBYTE p = 0; p < 5; ++p)
    {
        ptr = (ULONG)(screen + (ULONG)p * BYTESPERROW);
        cop[1] = ptr >> 16;
        cop[3] = ptr & 0xFFFF;
        cop += 4;
    }
}

static void InitCopper(UBYTE *screen)
{
    UWORD *cop = Copper;

    // OCS 320x256, 5 bitplanes, interleaved bitmap layout.
    CopperPut(&cop, 0x008E, 0x2C81); // DIWSTRT
    CopperPut(&cop, 0x0090, 0x2CC1); // DIWSTOP
    CopperPut(&cop, 0x0092, 0x0038); // DDFSTRT
    CopperPut(&cop, 0x0094, 0x00D0); // DDFSTOP
    CopperPut(&cop, 0x0100, BPLCON0_5BPL_LORES);
    CopperPut(&cop, 0x0102, 0x0000);        // BPLCON1
    CopperPut(&cop, 0x0104, 0x0000);        // BPLCON2
    CopperPut(&cop, 0x0106, 0x0000);        // BPLCON3, AGA safe reset
    CopperPut(&cop, 0x010C, 0x0000);        // BPLCON4, AGA safe reset
    CopperPut(&cop, 0x01FC, 0x0000);        // FMODE, AGA safe OCS fetch
    CopperPut(&cop, 0x0108, EFFECT_BPLMOD); // BPL1MOD, odd planes
    CopperPut(&cop, 0x010A, EFFECT_BPLMOD); // BPL2MOD, even planes

    CopperBplPtrWords = cop;

    for (UBYTE p = 0; p < 5; ++p)
    {
        CopperPut(&cop, 0x00E0 + (p << 2), 0x0000);
        CopperPut(&cop, 0x00E2 + (p << 2), 0x0000);
    }

    CopperPut(&cop, 0x0180, 0x0000);
    CopperPut(&cop, 0x0182, 0x0222);
    CopperPut(&cop, 0x0184, 0x0444);
    CopperPut(&cop, 0x0186, 0x0666);
    CopperPut(&cop, 0x0188, 0x0888);
    CopperPut(&cop, 0x018A, 0x0AAA);
    CopperPut(&cop, 0x018C, 0x0CCC);
    CopperPut(&cop, 0x018E, 0x0EEE);

    for (UBYTE i = 8; i < 32; ++i)
    {
        UWORD v = i >> 1;
        CopperPut(&cop, 0x0180 + (i << 1), (v << 8) | (v << 4) | v);
    }

    *cop++ = 0xFFFF;
    *cop++ = 0xFFFE;

    SetCopperScreen(screen);
    StartCopper(Copper);
}

static void ClearWholeScreen(UBYTE *screen)
{
    ULONG *dst = (ULONG *)screen;

    for (ULONG i = 0; i < (EFFECT_SCREEN_BYTES >> 2); ++i)
    {
        *dst++ = 0;
    }
}

static void InitSinTab(void)
{
    static const WORD q[65] =
        {
            0, 3, 6, 9, 13, 16, 19, 22,
            25, 28, 31, 34, 37, 40, 43, 46,
            49, 52, 55, 57, 60, 63, 65, 68,
            70, 73, 75, 77, 80, 82, 84, 86,
            88, 90, 92, 94, 95, 97, 98, 100,
            101, 102, 104, 105, 106, 107, 108, 109,
            110, 111, 111, 112, 113, 113, 114, 114,
            115, 115, 115, 116, 116, 116, 116, 116,
            116};

    for (UWORD i = 0; i < 65; ++i)
    {
        SinTab[i] = q[i];
        SinTab[128 - i] = q[i];
        SinTab[128 + i] = -q[i];
        SinTab[(256 - i) & 255] = -q[i];
    }
}

static void InitTwistTables(void)
{
    for (UWORD i = 0; i < 256; ++i)
    {
        WORD s = SinTab[i];
        WORD c = SinTab[(i + 64) & 255];
        WORD w = 176 + (c >> 1);

        if (w < TWIST_MIN_WIDTH)
            w = TWIST_MIN_WIDTH;
        if (w > TWIST_MAX_WIDTH)
            w = TWIST_MAX_WIDTH;
        w &= 0xFFF0;

        WidthTab[i] = w;
        OffsetTab[i] = s >> 1;
    }
}

static void ClearTextStrip(void)
{
    UBYTE *dst = TextStrip;

    for (UWORD i = 0; i < TWIST_STRIP_BYTES * TWIST_HEIGHT; ++i)
    {
        *dst++ = 0;
    }
}

static void SetStripPixel(UWORD x, UWORD y)
{
    UBYTE *dst = TextStrip + (ULONG)y * TWIST_STRIP_BYTES + (x >> 3);
    *dst |= 0x80 >> (x & 7);
}

static void DrawTallStripChar(char c, UWORD px)
{
    const UBYTE *glyph = ASCIIFont8x8[(UBYTE)c];

    for (UBYTE gy = 0; gy < 8; ++gy)
    {
        UBYTE bits = glyph[gy];
        UWORD sy = gy << 3;

        for (UBYTE ry = 0; ry < 8; ++ry)
        {
            for (UBYTE x = 0; x < 8; ++x)
            {
                if (bits & (1 << x))
                {
                    SetStripPixel(px + x, sy + ry);
                }
            }
        }
    }
}

static void BuildTextStrip(void)
{
    const char *msg = "    *** DEEP4 AMIGA TWIST SCROLLER - 320X256 - 5BPL - LWMF ***    ";
    const char *t = msg;
    UWORD x = 0;

    ClearTextStrip();

    while (x < TWIST_STRIP_WIDTH - 8)
    {
        DrawTallStripChar(*t++, x);
        x += 8;

        if (!*t)
        {
            t = msg;
        }
    }
}

static void RenderTwistScroller(UBYTE *screen, UWORD frame)
{
    UBYTE *rowBase = screen + (ULONG)TWIST_TOP * EFFECT_SCREEN_STRIDE;
    UBYTE *stripRow = TextStrip;

    for (UWORD y = 0; y < TWIST_HEIGHT; ++y)
    {
        UWORD phase = (frame + (y << 2)) & 255;
        UWORD width = WidthTab[phase];
        UWORD dstX = TWIST_CENTER_X - (width >> 1);
        UWORD srcBase = ((frame << 1) + OffsetTab[phase]) & TWIST_STRIP_MASK;

        for (UWORD x = 0; x < width; ++x)
        {
            UWORD sx = (srcBase + x) & TWIST_STRIP_MASK;
            UBYTE src = stripRow[sx >> 3];

            if (src & (0x80 >> (sx & 7)))
            {
                UWORD dx = dstX + x;
                UBYTE *dst = rowBase + (dx >> 3);
                UBYTE bit = 0x80 >> (dx & 7);

                dst[0 * BYTESPERROW] |= bit;
                dst[1 * BYTESPERROW] |= bit;
                dst[2 * BYTESPERROW] |= bit;
                dst[3 * BYTESPERROW] |= bit;
                dst[4 * BYTESPERROW] |= bit;
            }
        }

        rowBase += EFFECT_SCREEN_STRIDE;
        stripRow += TWIST_STRIP_BYTES;
    }
}

int main(void)
{
    UBYTE draw = 1;
    UWORD frame = 0;

    lwmf_LoadGraphicsLib();
    lwmf_InitScreenBitmaps();

    Copper = (UWORD *)AllocMem(COPPER_BYTES, MEMF_CHIP | MEMF_CLEAR);
    TextStrip = (UBYTE *)AllocMem((ULONG)TWIST_STRIP_BYTES * TWIST_HEIGHT, MEMF_CHIP | MEMF_CLEAR);

    InitSinTab();
    InitTwistTables();
    BuildTextStrip();
    ClearWholeScreen(ScreenBitmapMem[0]);
    ClearWholeScreen(ScreenBitmapMem[1]);

    lwmf_TakeOverOS();
    *SPR0PTH = (ULONG)BlankMousePointer >> 16;
    *SPR0PTL = (ULONG)BlankMousePointer & 0xFFFF;
    InitCopper(ScreenBitmapMem[0]);

    while (*CIAA_PRA & 0x40)
    {
        ClearWholeScreen(ScreenBitmapMem[draw]);

#if DEBUG_BLACK_ONLY == 0
        RenderTwistScroller(ScreenBitmapMem[draw], frame);
#endif

        lwmf_WaitVertBlank();
        SetCopperScreen(ScreenBitmapMem[draw]);
        draw ^= 1;
        ++frame;
    }

    lwmf_WaitBlitter();
    lwmf_ReleaseOS();

    FreeMem(TextStrip, (ULONG)TWIST_STRIP_BYTES * TWIST_HEIGHT);
    FreeMem(Copper, COPPER_BYTES);
    lwmf_CleanupScreenBitmaps();
    lwmf_CloseLibraries();

    return 0;
}
