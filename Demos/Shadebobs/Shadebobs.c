//**********************************************************************
//* Shadebobs effect                                                   *
//* Amiga 500 OCS                                                      *
//*                                                                    *
//* (C) 2026 by Stefan Kubsch / Deep4                                  *
//*                                                                    *
//* Compile & link with:                                               *
//* make_Build.cmd / make_ADF.cmd                                      *
//*                                                                    *
//* Quit with mouse click                                              *
//**********************************************************************

#include "lwmf/lwmf.h"

// ---------------------------------------------------------------------
// Shadebobs
// ---------------------------------------------------------------------

#define BOB_SIZE 32
#define BOB_WORDS_PER_ROW 3
#define BOB_SHIFT_COUNT 16
#define PATH_STEPS 512
#define SHADEBOB_RADIUS 11
#define BOBCMD_MAX 80

struct BobCmd
{
    UWORD Offset;
    UWORD Mask;
};

struct BobFrame
{
    UBYTE *Dest0;
    struct BobCmd *Cmd0;
    UBYTE *Dest1;
    struct BobCmd *Cmd1;
    UWORD Count0;
    UWORD Count1;
};

struct BobCmdList
{
    UWORD Count;
    struct BobCmd Cmd[BOBCMD_MAX];
};

#define PALETTE_STEPS 64
#define PALETTE_UPDATE_MASK 3

static const UWORD PurpleHueCycle[32] =
    {
        0x500, 0x700, 0x900, 0xb00,
        0xd00, 0xf00, 0xf02, 0xf04,
        0xe06, 0xc08, 0xa0a, 0x80c,
        0x60e, 0x40f, 0x20f, 0x00f,
        0x20f, 0x40f, 0x60e, 0x80c,
        0xa0a, 0xc08, 0xe06, 0xf04,
        0xf02, 0xf00, 0xd00, 0xb00,
        0x900, 0x700, 0x500, 0x400};

static const UBYTE ShadeRamp[32] =
    {
        0, 0, 1, 1, 2, 2, 3, 3,
        4, 4, 5, 5, 6, 7, 7, 8,
        8, 9, 9, 10, 10, 11, 12, 12,
        13, 13, 14, 14, 15, 15, 15, 15};

static UWORD PaletteCycle[PALETTE_STEPS][32];

static const UBYTE BobXPathPacked[PATH_STEPS] =
    {
        228, 225, 223, 220, 217, 214, 211, 207, 204, 201, 197, 193, 190, 186, 182, 178,
        175, 171, 167, 163, 159, 155, 151, 147, 143, 139, 135, 130, 126, 122, 119, 115,
        111, 107, 103, 99, 96, 92, 89, 85, 82, 78, 75, 72, 69, 66, 63, 61,
        58, 56, 53, 51, 49, 47, 45, 43, 42, 40, 39, 38, 37, 36, 35, 35,
        34, 34, 34, 34, 34, 35, 35, 36, 36, 37, 38, 40, 41, 42, 44, 46,
        48, 50, 52, 54, 56, 59, 62, 64, 67, 70, 73, 76, 80, 83, 86, 90,
        93, 97, 101, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144, 148, 152,
        156, 160, 164, 168, 172, 176, 180, 184, 187, 191, 195, 198, 202, 205, 208, 212,
        215, 218, 221, 224, 226, 229, 232, 234, 236, 238, 240, 242, 244, 246, 247, 248,
        250, 251, 252, 252, 253, 253, 254, 254, 254, 254, 254, 253, 253, 252, 251, 250,
        249, 248, 246, 245, 243, 241, 239, 237, 235, 232, 230, 227, 225, 222, 219, 216,
        213, 209, 206, 203, 199, 196, 192, 189, 185, 181, 177, 173, 169, 165, 161, 157,
        153, 149, 145, 141, 137, 133, 129, 125, 121, 117, 113, 109, 106, 102, 98, 94,
        91, 87, 84, 81, 77, 74, 71, 68, 65, 62, 60, 57, 55, 53, 50, 48,
        46, 45, 43, 41, 40, 39, 38, 37, 36, 35, 35, 34, 34, 34, 34, 34,
        35, 35, 36, 37, 38, 39, 40, 41, 43, 45, 46, 48, 50, 53, 55, 57,
        60, 63, 65, 68, 71, 74, 77, 81, 84, 87, 91, 95, 98, 102, 106, 110,
        113, 117, 121, 125, 129, 133, 137, 141, 145, 149, 153, 158, 162, 166, 169, 173,
        177, 181, 185, 189, 192, 196, 199, 203, 206, 210, 213, 216, 219, 222, 225, 227,
        230, 232, 235, 237, 239, 241, 243, 245, 246, 248, 249, 250, 251, 252, 253, 253,
        254, 254, 254, 254, 254, 253, 253, 252, 252, 251, 250, 248, 247, 246, 244, 242,
        240, 238, 236, 234, 232, 229, 226, 224, 221, 218, 215, 212, 208, 205, 202, 198,
        195, 191, 187, 184, 180, 176, 172, 168, 164, 160, 156, 152, 148, 144, 140, 136,
        132, 128, 124, 120, 116, 112, 108, 104, 101, 97, 93, 90, 86, 83, 80, 76,
        73, 70, 67, 64, 62, 59, 56, 54, 52, 50, 48, 46, 44, 42, 41, 40,
        38, 37, 36, 36, 35, 35, 34, 34, 34, 34, 34, 35, 35, 36, 37, 38,
        39, 40, 42, 43, 45, 47, 49, 51, 53, 56, 58, 61, 63, 66, 69, 72,
        75, 79, 82, 85, 89, 92, 96, 99, 103, 107, 111, 115, 119, 123, 127, 131,
        135, 139, 143, 147, 151, 155, 159, 163, 167, 171, 175, 179, 182, 186, 190, 194,
        197, 201, 204, 207, 211, 214, 217, 220, 223, 226, 228, 231, 233, 235, 238, 240,
        242, 243, 245, 247, 248, 249, 250, 251, 252, 253, 253, 254, 254, 254, 254, 254,
        253, 253, 252, 251, 250, 249, 248, 247, 245, 243, 242, 240, 238, 235, 233, 231};

static const UBYTE BobYPathPacked[PATH_STEPS] =
    {
        194, 193, 192, 191, 189, 188, 186, 184, 182, 179, 177, 174, 171, 168, 165, 162,
        158, 155, 151, 148, 144, 140, 136, 132, 128, 124, 120, 116, 112, 108, 103, 99,
        95, 91, 87, 83, 80, 76, 72, 69, 65, 62, 58, 55, 52, 50, 47, 44,
        42, 40, 38, 36, 34, 33, 32, 30, 30, 29, 28, 28, 28, 28, 28, 29,
        30, 31, 32, 33, 35, 36, 38, 40, 42, 45, 47, 50, 53, 56, 59, 62,
        66, 69, 73, 76, 80, 84, 88, 92, 96, 100, 104, 108, 112, 116, 121, 125,
        129, 133, 137, 141, 144, 148, 152, 155, 159, 162, 166, 169, 172, 174, 177, 180,
        182, 184, 186, 188, 190, 191, 192, 194, 194, 195, 196, 196, 196, 196, 196, 195,
        194, 193, 192, 191, 189, 188, 186, 184, 182, 179, 177, 174, 171, 168, 165, 162,
        158, 155, 151, 148, 144, 140, 136, 132, 128, 124, 120, 116, 112, 108, 103, 99,
        95, 91, 87, 83, 80, 76, 72, 69, 65, 62, 58, 55, 52, 50, 47, 44,
        42, 40, 38, 36, 34, 33, 32, 30, 30, 29, 28, 28, 28, 28, 28, 29,
        30, 31, 32, 33, 35, 36, 38, 40, 42, 45, 47, 50, 53, 56, 59, 62,
        66, 69, 73, 76, 80, 84, 88, 92, 96, 100, 104, 108, 112, 116, 121, 125,
        129, 133, 137, 141, 144, 148, 152, 155, 159, 162, 166, 169, 172, 174, 177, 180,
        182, 184, 186, 188, 190, 191, 192, 194, 194, 195, 196, 196, 196, 196, 196, 195,
        194, 193, 192, 191, 189, 188, 186, 184, 182, 179, 177, 174, 171, 168, 165, 162,
        158, 155, 151, 148, 144, 140, 136, 132, 128, 124, 120, 116, 112, 108, 103, 99,
        95, 91, 87, 83, 80, 76, 72, 69, 65, 62, 58, 55, 52, 50, 47, 44,
        42, 40, 38, 36, 34, 33, 32, 30, 30, 29, 28, 28, 28, 28, 28, 29,
        30, 31, 32, 33, 35, 36, 38, 40, 42, 45, 47, 50, 53, 56, 59, 62,
        66, 69, 73, 76, 80, 84, 88, 92, 96, 100, 104, 108, 112, 116, 121, 125,
        129, 133, 137, 141, 144, 148, 152, 155, 159, 162, 166, 169, 172, 174, 177, 180,
        182, 184, 186, 188, 190, 191, 192, 194, 194, 195, 196, 196, 196, 196, 196, 195,
        194, 193, 192, 191, 189, 188, 186, 184, 182, 179, 177, 174, 171, 168, 165, 162,
        158, 155, 151, 148, 144, 140, 136, 132, 128, 124, 120, 116, 112, 108, 103, 99,
        95, 91, 87, 83, 80, 76, 72, 69, 65, 62, 58, 55, 52, 50, 47, 44,
        42, 40, 38, 36, 34, 33, 32, 30, 30, 29, 28, 28, 28, 28, 28, 29,
        30, 31, 32, 33, 35, 36, 38, 40, 42, 45, 47, 50, 53, 56, 59, 62,
        66, 69, 73, 76, 80, 84, 88, 92, 96, 100, 104, 108, 112, 116, 121, 125,
        129, 133, 137, 141, 144, 148, 152, 155, 159, 162, 166, 169, 172, 174, 177, 180,
        182, 184, 186, 188, 190, 191, 192, 194, 194, 195, 196, 196, 196, 196, 196, 195};

static struct BobCmdList BobCmdList[BOB_SHIFT_COUNT];
static struct BobFrame BobFrame[PATH_STEPS];

void DrawShadebobsFrameFastAsm(__reg("a0") struct BobFrame *frame);

static void Init_ScreenBitmapSingle(void)
{
    const ULONG screenBytes = (ULONG)BYTESPERROW * NUMBEROFBITPLANES * SCREENHEIGHT;

    ScreenBitmapMem[0] = (UBYTE *)AllocMem(screenBytes, MEMF_CHIP | MEMF_CLEAR);

    lwmf_InitBitMap(&ScreenBitmapStruct[0], NUMBEROFBITPLANES, SCREENWIDTH, SCREENHEIGHT);
    ScreenBitmapStruct[0].BytesPerRow = BYTESPERROW * NUMBEROFBITPLANES;

    for (UBYTE p = 0; p < NUMBEROFBITPLANES; ++p)
    {
        ScreenBitmapStruct[0].Planes[p] = (PLANEPTR)(ScreenBitmapMem[0] + (ULONG)p * BYTESPERROW);
    }

    ScreenBitmap[0] = &ScreenBitmapStruct[0];
}

static void BuildBobMask(void)
{
    for (UWORD shift = 0; shift < BOB_SHIFT_COUNT; ++shift)
    {
        UWORD mask[BOB_SIZE][BOB_WORDS_PER_ROW];
        UWORD rowOffset = 0;
        UWORD count = 0;

        for (UWORD row = 0; row < BOB_SIZE; ++row)
        {
            for (UWORD word = 0; word < BOB_WORDS_PER_ROW; ++word)
            {
                mask[row][word] = 0;
            }
        }

        for (UWORD y = 0; y < BOB_SIZE; ++y)
        {
            for (UWORD x = 0; x < BOB_SIZE; ++x)
            {
                const WORD dx = x - (BOB_SIZE >> 1);
                const WORD dy = y - (BOB_SIZE >> 1);
                const WORD dist2 = (dx * dx) + (dy * dy);

                if (dist2 <= (SHADEBOB_RADIUS * SHADEBOB_RADIUS))
                {
                    const UWORD bitPos = x + shift;

                    if (bitPos < 16)
                    {
                        mask[y][0] |= (UWORD)(0x8000 >> bitPos);
                    }
                    else if (bitPos < 32)
                    {
                        mask[y][1] |= (UWORD)(0x8000 >> (bitPos - 16));
                    }
                    else
                    {
                        mask[y][2] |= (UWORD)(0x8000 >> (bitPos - 32));
                    }
                }
            }
        }

        for (UWORD row = 0; row < BOB_SIZE; ++row)
        {
            for (UWORD word = 0; word < BOB_WORDS_PER_ROW; ++word)
            {
                const UWORD m = mask[row][word];

                if (m)
                {
                    BobCmdList[shift].Cmd[count].Offset = rowOffset + (word << 1);
                    BobCmdList[shift].Cmd[count].Mask = m;
                    ++count;
                }
            }

            rowOffset += SCREENWIDTHTOTAL;
        }

        BobCmdList[shift].Count = count;
    }
}

static void BuildBobPath(void)
{
    UBYTE *screenBase = (UBYTE *)ScreenBitmapStruct[0].Planes[0];

    for (UWORD i = 0; i < PATH_STEPS; ++i)
    {
        const UBYTE x0 = BobXPathPacked[i];
        const UBYTE y0 = BobYPathPacked[i];
        const UWORD shift0 = x0 & 15;
        const UWORD idx = i ^ (PATH_STEPS >> 1);
        const UBYTE x1 = BobXPathPacked[idx];
        const UBYTE y1 = BobYPathPacked[idx];
        const UWORD shift1 = x1 & 15;
        UWORD rowOffset0 = 0;
        UWORD rowOffset1 = 0;

        for (UBYTE y = 0; y < y0; ++y)
        {
            rowOffset0 += SCREENWIDTHTOTAL;
        }

        for (UBYTE y = 0; y < y1; ++y)
        {
            rowOffset1 += SCREENWIDTHTOTAL;
        }

        BobFrame[i].Dest0 = screenBase + rowOffset0 + ((x0 >> 4) << 1);
        BobFrame[i].Cmd0 = BobCmdList[shift0].Cmd;
        BobFrame[i].Dest1 = screenBase + rowOffset1 + ((x1 >> 4) << 1);
        BobFrame[i].Cmd1 = BobCmdList[shift1].Cmd;
        BobFrame[i].Count0 = BobCmdList[shift0].Count - 1;
        BobFrame[i].Count1 = BobCmdList[shift1].Count - 1;
    }
}

static UWORD ScaleRGB4(UWORD c, UWORD s)
{
    UWORD r = (c >> 8) & 15;
    UWORD g = (c >> 4) & 15;
    UWORD b = c & 15;

    r = (r * s) >> 4;
    g = (g * s) >> 4;
    b = (b * s) >> 4;

    return (r << 8) | (g << 4) | b;
}

static void BuildPaletteCycle(void)
{
    for (UWORD p = 0; p < PALETTE_STEPS; ++p)
    {
        const UWORD hueIndex = p >> 1;
        const UWORD hueFrac = (p & 1) << 3;
        const UWORD colorA = lwmf_RGBLerp(PurpleHueCycle[hueIndex & 31], PurpleHueCycle[(hueIndex + 1) & 31], hueFrac, 16);
        const UWORD colorB = lwmf_RGBLerp(PurpleHueCycle[(hueIndex + 6) & 31], PurpleHueCycle[(hueIndex + 7) & 31], hueFrac, 16);

        PaletteCycle[p][0] = 0;

        for (UWORD i = 1; i < 32; ++i)
        {
            UWORD base;

            if (i < 20)
            {
                base = lwmf_RGBLerp(colorA, colorB, i >> 1, 16);
            }
            else
            {
                UWORD t = i - 20;
                t += t >> 1;
                if (t > 15)
                {
                    t = 15;
                }
                base = lwmf_RGBLerp(colorB, 0xf8f, t, 16);
            }

            PaletteCycle[p][i] = ScaleRGB4(base, ShadeRamp[i]);
        }
    }
}

// ---------------------------------------------------------------------
// Copper / palette
// ---------------------------------------------------------------------

static UWORD *CopperList = NULL;
static ULONG CopperListSize = 0;
static UWORD ColorValueIdx[32];

// Needed memory for copper:
// 8 for display and DMA
// 2 for bitplane setup
// 4 for BPLCON1 and BPLCON2 and interleaved bitmaps
// 2 for interleaved bitmaps
// 4 per bitplane for bitplane pointers
// per color: 2 (32 colors) = 64
// 2 for copper end marker
//
// So: (8+2+4+2)+4*NUMBEROFBITPLANES+2*32+2
#define COPPER_FIXED_WORDS ((82 + 4 * NUMBEROFBITPLANES) * 2)

static void Init_CopperList(void)
{
    const ULONG CopperListLength = COPPER_FIXED_WORDS;
    CopperListSize = CopperListLength * sizeof(UWORD);

    CopperList = (UWORD *)AllocMem(CopperListSize, MEMF_CHIP | MEMF_CLEAR);

    UWORD Index = 0;

    // PAL display window
    CopperList[Index++] = 0x08E;
    CopperList[Index++] = 0x2C81; // DIWSTRT
    CopperList[Index++] = 0x090;
    CopperList[Index++] = 0x2CC1; // DIWSTOP
    CopperList[Index++] = 0x092;
    CopperList[Index++] = 0x0038; // DDFSTRT
    CopperList[Index++] = 0x094;
    CopperList[Index++] = 0x00D0; // DDFSTOP

    // 5 bitplanes
    CopperList[Index++] = 0x100;
    CopperList[Index++] = (UWORD)((NUMBEROFBITPLANES << 12) | 0x0200);

    CopperList[Index++] = 0x102;
    CopperList[Index++] = 0x0000; // BPLCON1
    CopperList[Index++] = 0x104;
    CopperList[Index++] = 0x0000; // BPLCON2

    // Interleaved bitmaps
    CopperList[Index++] = 0x108;
    CopperList[Index++] = BYTESPERROW * (NUMBEROFBITPLANES - 1);

    CopperList[Index++] = 0x10A;
    CopperList[Index++] = BYTESPERROW * (NUMBEROFBITPLANES - 1);

    // Bitplane pointers
    ULONG Ptr = (ULONG)ScreenBitmap[0]->Planes[0];

    for (UWORD p = 0; p < NUMBEROFBITPLANES; ++p)
    {
        CopperList[Index++] = (UWORD)(0x0E0 + (p * 4));
        CopperList[Index++] = (UWORD)(Ptr >> 16);

        CopperList[Index++] = (UWORD)(0x0E2 + (p * 4));
        CopperList[Index++] = (UWORD)(Ptr & 0xFFFF);

        Ptr += BYTESPERROW;
    }

    for (UBYTE c = 0; c < 32; ++c)
    {
        CopperList[Index++] = (UWORD)(0x0180 + (c << 1));
        ColorValueIdx[c] = Index;
        CopperList[Index++] = PaletteCycle[0][c];
    }

    CopperList[Index++] = 0xFFFF;
    CopperList[Index++] = 0xFFFE;
}

static void UpdateCopperPalette(UWORD palettePhase)
{
    UWORD *colors = PaletteCycle[palettePhase & (PALETTE_STEPS - 1)];

    for (UBYTE c = 0; c < 32; ++c)
    {
        CopperList[ColorValueIdx[c]] = colors[c];
    }
}

static void Activate_CopperList(void)
{
    *COP1LC = (ULONG)CopperList;
}

// ---------------------------------------------------------------------
// Cleanup / main
// ---------------------------------------------------------------------

static void Cleanup_All(void)
{
    FreeMem(CopperList, CopperListSize);
    CopperList = NULL;
    lwmf_CleanupScreenBitmaps();
    lwmf_CleanupAll();
}

int main(void)
{
    lwmf_LoadGraphicsLib();
    Init_ScreenBitmapSingle();
    BuildBobMask();
    BuildBobPath();
    BuildPaletteCycle();
    Init_CopperList();
    lwmf_TakeOverOS();
    Activate_CopperList();

    UWORD Phase = 0;

    while (*CIAA_PRA & 0x40)
    {
        lwmf_WaitVertBlank();

        if (!(Phase & PALETTE_UPDATE_MASK))
        {
            UpdateCopperPalette(Phase >> 2);
        }

        DrawShadebobsFrameFastAsm(&BobFrame[Phase]);
        Phase = (UWORD)((Phase + 1) & (PATH_STEPS - 1));
    }

    Cleanup_All();
    return 0;
}
