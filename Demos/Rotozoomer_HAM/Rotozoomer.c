//**********************************************************************
//* 4x4 HAM7 Rotozoomer                                                *
//*                                                                    *
//* 4 DMA bitplanes, HAM control via BPL5DAT/BPL6DAT, 80 columns      *
//* Amiga 500 OCS, 68000                                               *
//*                                                                    *
//* (C) 2026 by Stefan Kubsch/Deep4                                    *
//* Project for vbcc                                                   *
//*                                                                    *
//* Compile & link with:                                               *
//* make_Rotozoomer.cmd                                                *
//*                                                                    *
//* Quit with mouse click                                              *
//**********************************************************************

#include "lwmf/lwmf.h"

// ---------------------------------------------------------------------
// Debugging
// ---------------------------------------------------------------------

#define DEBUG 1

#if DEBUG
#define DBG_COLOR(c) (*COLOR00 = (c))
#else
#define DBG_COLOR(c) ((void)0)
#endif

// ---------------------------------------------------------------------
// Assembler interface
// ---------------------------------------------------------------------

extern void RenderFrameAsm(__reg("a0") UBYTE* Dest);

// ---------------------------------------------------------------------
// Effect constants
// ---------------------------------------------------------------------

#define TEXTURE_FILENAME        "gfx/128x128_ham.iff"
#define TEXTURE_SOURCE_WIDTH    128
#define TEXTURE_SOURCE_HEIGHT   128
#define TEXTURE_WIDTH           TEXTURE_SOURCE_WIDTH
#define TEXTURE_HEIGHT          TEXTURE_SOURCE_HEIGHT
#define TEXTURE_PACKED_STRIDE   ((UWORD)sizeof(ULONG))
#define TEXTURE_PACKED_ROW_BYTES ((UWORD)(TEXTURE_WIDTH * TEXTURE_PACKED_STRIDE))
#define TEXTURE_PACKED_TOTAL_BYTES ((ULONG)TEXTURE_HEIGHT * (ULONG)TEXTURE_PACKED_ROW_BYTES)
#define TEXTURE_PACKED_CENTER   (TEXTURE_PACKED_TOTAL_BYTES / 2)

#define HAM_DISPLAY_BPU         7
#define HAM_CONTROL_WORD_P5     0x7777
#define HAM_CONTROL_WORD_P6     0xCCCC
#define HAM_BACKGROUND_RGB4     0x000

#define CHUNKY_PIXEL_SIZE       4
#define ROTO_COLUMNS            80
#define ROTO_ROWS               48
#define ROTO_PAIR_COUNT         (ROTO_COLUMNS / 2)
#define ROTO_DISPLAY_WIDTH      (ROTO_COLUMNS * CHUNKY_PIXEL_SIZE)
#define ROTO_DISPLAY_HEIGHT     (ROTO_ROWS * CHUNKY_PIXEL_SIZE)
#define ROTO_HALF_COLUMNS       (ROTO_COLUMNS / 2)
#define ROTO_HALF_ROWS          (ROTO_ROWS / 2)

#define ROTO_START_X            0
#define ROTO_START_BYTE         (ROTO_START_X >> 3)
#define INTERLEAVED_STRIDE      (BYTESPERROW * NUMBEROFBITPLANES)
#define ROTO_FETCH_BYTES        (ROTO_DISPLAY_WIDTH / 8)
#define ROTO_REPEAT_MOD         ((UWORD)(-(WORD)ROTO_FETCH_BYTES))
#define ROTO_ADVANCE_MOD        ((UWORD)(INTERLEAVED_STRIDE - ROTO_FETCH_BYTES))
#define ROTO_MOD_SWITCH_COUNT   ((ROTO_ROWS - 1) * 2)

#define ROTO_VPOS_START         0x2Cu
#define ROTO_VPOS_STOP          (ROTO_VPOS_START + ROTO_DISPLAY_HEIGHT)
#define ROTO_DIWSTRT            (UWORD)(((ROTO_VPOS_START & 0xFF) << 8) | 0x0081)
#define ROTO_DIWSTOP            (UWORD)(((ROTO_VPOS_STOP  & 0xFF) << 8) | 0x00C1)
#define ROTO_DDFSTRT            0x0038
#define ROTO_DDFSTOP            0x00D0

#define SCREEN_COLORS           32
#define ROTO_ZOOM_BASE          384
#define ROTO_ZOOM_AMPLITUDE     128
#define ROTO_ZOOM_STEPS         32
#define ROTO_ANGLE_PHASE_STEP   2
#define ROTO_ANGLE_STEPS        (256 / ROTO_ANGLE_PHASE_STEP)
#define ROTO_DELTA_SCALE        3072

// ---------------------------------------------------------------------
// Delta table
// ---------------------------------------------------------------------

typedef struct
{
    WORD DuDx;
    WORD DvDx;
} RotoDelta;

WORD MoveTab[256];
RotoDelta* DeltaTab = NULL;
static ULONG DeltaTabSize = 0;

// ---------------------------------------------------------------------
// Sine table
// ---------------------------------------------------------------------

const UBYTE SinTab256[256] =
{
    32,32,33,34,35,35,36,37,38,38,39,40,41,41,42,43,44,44,45,46,46,47,48,48,49,50,50,51,51,52,53,53,
    54,54,55,55,56,56,57,57,58,58,59,59,59,60,60,60,61,61,61,61,62,62,62,62,62,63,63,63,63,63,63,63,
    63,63,63,63,63,63,63,63,62,62,62,62,62,61,61,61,61,60,60,60,59,59,59,58,58,57,57,56,56,55,55,54,
    54,53,53,52,51,51,50,50,49,48,48,47,46,46,45,44,44,43,42,41,41,40,39,38,38,37,36,35,35,34,33,32,
    32,31,30,29,28,28,27,26,25,25,24,23,22,22,21,20,19,19,18,17,17,16,15,15,14,13,13,12,12,11,10,10,
     9, 9, 8, 8, 7, 7, 6, 6, 5, 5, 4, 4, 4, 3, 3, 3, 2, 2, 2, 2, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0,
     0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9,
     9,10,10,11,12,12,13,13,14,15,15,16,17,17,18,19,19,20,21,22,22,23,24,25,25,26,27,28,28,29,30,31
};

// ---------------------------------------------------------------------
// Texture, palette and animation state
// ---------------------------------------------------------------------

static UBYTE* TexturePacked = NULL;
ULONG* TexturePackedMid = NULL;
static ULONG TexturePackedSize = 0;
static UWORD DisplayPalette[SCREEN_COLORS];

UBYTE AnglePhase = 0;
UBYTE ZoomPhase  = 0;
UBYTE MovePhaseX = 0;
UBYTE MovePhaseY = 64;

// ---------------------------------------------------------------------
// Rotozoomer
// ---------------------------------------------------------------------

static UBYTE GetPlanarPixel(const struct BitMap* BitMap, UWORD X, UWORD Y, UBYTE Depth)
{
    const ULONG RowOffset = (ULONG)Y * (ULONG)BitMap->BytesPerRow;
    const ULONG ByteOffset = RowOffset + (ULONG)(X >> 3);
    const UBYTE Mask = (UBYTE)(0x80 >> (X & 7));
    UBYTE Pixel = 0;

    for (UBYTE Plane = 0; Plane < Depth; ++Plane)
    {
        const UBYTE* PlaneBase = (const UBYTE*)BitMap->Planes[Plane];

        if (PlaneBase[ByteOffset] & Mask)
        {
            Pixel |= (UBYTE)(1 << Plane);
        }
    }

    return Pixel;
}

static void BuildMoveTable(void)
{
    for (UWORD i = 0; i < 256; ++i)
    {
        MoveTab[i] = (WORD)(((WORD)SinTab256[i] - 32) << 8);
    }
}

static void BuildDeltaTable(void)
{
    DeltaTabSize = (ULONG)ROTO_ZOOM_STEPS * (ULONG)ROTO_ANGLE_STEPS * sizeof(RotoDelta);
    DeltaTab = (RotoDelta*)lwmf_AllocCpuMem(DeltaTabSize, MEMF_CLEAR);

    for (UWORD ZoomIdx = 0; ZoomIdx < ROTO_ZOOM_STEPS; ++ZoomIdx)
    {
        const LONG Zoom =
            (LONG)ROTO_ZOOM_BASE - (LONG)ROTO_ZOOM_AMPLITUDE +
            (((LONG)ZoomIdx * ((LONG)ROTO_ZOOM_AMPLITUDE * 2L)) / (LONG)(ROTO_ZOOM_STEPS - 1));

        for (UWORD AngleIdx = 0; AngleIdx < ROTO_ANGLE_STEPS; ++AngleIdx)
        {
            const UBYTE Angle = (UBYTE)(AngleIdx * ROTO_ANGLE_PHASE_STEP);
            const LONG  SinV  = (LONG)((WORD)SinTab256[Angle] - 32);
            const LONG  CosV  = (LONG)((WORD)SinTab256[(UBYTE)(Angle + 64)] - 32);

            RotoDelta* Delta = &DeltaTab[(ULONG)ZoomIdx * ROTO_ANGLE_STEPS + AngleIdx];

            Delta->DuDx = (WORD)((CosV * ROTO_DELTA_SCALE) / Zoom);
            Delta->DvDx = (WORD)((SinV * ROTO_DELTA_SCALE) / Zoom);
        }
    }
}

static ULONG PackHamContribution(UWORD Color)
{
    const UBYTE R = (UBYTE)((Color >> 8) & 0x0F);
    const UBYTE G = (UBYTE)((Color >> 4) & 0x0F);
    const UBYTE B = (UBYTE)( Color       & 0x0F);

    UBYTE PlaneNibble[4];

    for (UBYTE Plane = 0; Plane < 4; ++Plane)
    {
        const UBYTE BitR = (UBYTE)((R >> Plane) & 1);
        const UBYTE BitG = (UBYTE)((G >> Plane) & 1);
        const UBYTE BitB = (UBYTE)((B >> Plane) & 1);

        PlaneNibble[Plane] = (UBYTE)((BitR << 3) | (BitG << 2) | (BitB << 1) | BitB);
    }

    /*
     * Packed result for the first texel in the pair:
     * [P3|P2|P1|P0] with the nibble in the high half of each byte.
     * The assembler derives the second-texel contribution via >> 4.
     */
    return
        ((ULONG)PlaneNibble[3] << 28) |
        ((ULONG)PlaneNibble[2] << 20) |
        ((ULONG)PlaneNibble[1] << 12) |
        ((ULONG)PlaneNibble[0] <<  4);
}

static void AllocTexturePacked(void)
{
    TexturePackedSize = TEXTURE_PACKED_TOTAL_BYTES;
    TexturePacked = (UBYTE*)lwmf_AllocCpuMem(TexturePackedSize, MEMF_CLEAR);
    TexturePackedMid = (ULONG*)(TexturePacked + TEXTURE_PACKED_CENTER);
}

static void StoreTextureColor(UWORD TexOffset, UWORD RGB12)
{
    *(ULONG*)(TexturePacked + TexOffset) = PackHamContribution(RGB12);
}

static void BuildDisplayPalette(const struct lwmf_Image* Image)
{
    for (UWORD i = 0; i < SCREEN_COLORS; ++i)
    {
        DisplayPalette[i] = 0x000;
    }

    DisplayPalette[0] = HAM_BACKGROUND_RGB4;

    const UWORD Limit = (Image->NumberOfColors < 16) ? Image->NumberOfColors : 16;

    for (UWORD i = 1; i < Limit; ++i)
    {
        DisplayPalette[i] = (UWORD)(Image->CRegs[i] & 0x0FFF);
    }
}

static void BuildTextureFromHAM(const struct lwmf_Image* Image)
{
    UWORD BasePal[16];

    for (UWORD i = 0; i < 16; ++i)
    {
        BasePal[i] = 0x000;
    }

    const UWORD Limit = (Image->NumberOfColors < 16) ? Image->NumberOfColors : 16;

    for (UWORD i = 0; i < Limit; ++i)
    {
        BasePal[i] = (UWORD)(Image->CRegs[i] & 0x0FFF);
    }

    for (UWORD Y = 0; Y < TEXTURE_SOURCE_HEIGHT; ++Y)
    {
        UWORD CurrentRGB = BasePal[0];
        const UWORD RowOffset = (UWORD)((ULONG)Y * (ULONG)TEXTURE_PACKED_ROW_BYTES);

        for (UWORD X = 0; X < TEXTURE_SOURCE_WIDTH; ++X)
        {
            const UBYTE Pixel = GetPlanarPixel(&Image->Image, X, Y, Image->Image.Depth);
            const UBYTE Data  = (UBYTE)(Pixel & 0x0F);
            const UBYTE Ctrl  = (UBYTE)(Pixel >> 4);
            const UWORD TexOffset = (UWORD)(RowOffset + (UWORD)(X * TEXTURE_PACKED_STRIDE));
            UWORD OutRGB;

            switch (Ctrl)
            {
                case 0:
                    OutRGB = BasePal[Data & 0x0F];
                    break;

                case 1:
                    OutRGB = (UWORD)((CurrentRGB & 0x0FF0) | Data);
                    break;

                case 2:
                    OutRGB = (UWORD)((CurrentRGB & 0x00FF) | ((UWORD)Data << 8));
                    break;

                default:
                    OutRGB = (UWORD)((CurrentRGB & 0x0F0F) | ((UWORD)Data << 4));
                    break;
            }

            CurrentRGB = OutRGB;
            StoreTextureColor(TexOffset, OutRGB);
        }
    }
}

static void InitTexture(void)
{
    struct lwmf_Image* Image = lwmf_LoadImage(TEXTURE_FILENAME);

    BuildDisplayPalette(Image);
    AllocTexturePacked();
    BuildTextureFromHAM(Image);
    lwmf_DeleteImage(Image);
}

// ---------------------------------------------------------------------
// Copper
// ---------------------------------------------------------------------

static UWORD CopperWaitWord(UWORD VPos)
{
    return (UWORD)(((VPos & 0xFFu) << 8) | 0x0001u);
}

static UWORD* CopperList = NULL;
static ULONG CopperListSize = 0;

static UWORD BPLPTH_Idx[NUMBEROFBITPLANES];
static UWORD BPLPTL_Idx[NUMBEROFBITPLANES];

static void Init_CopperList(void)
{
    const ULONG CopperWords = 24 + (4 * NUMBEROFBITPLANES) + (SCREEN_COLORS * 2) + (ROTO_MOD_SWITCH_COUNT * 6) + 2;

    CopperListSize = CopperWords * sizeof(UWORD);
    CopperList = (UWORD*)AllocMem(CopperListSize, MEMF_CHIP | MEMF_CLEAR);

    UWORD Index = 0;

    CopperList[Index++] = 0x008E;
    CopperList[Index++] = ROTO_DIWSTRT;
    CopperList[Index++] = 0x0090;
    CopperList[Index++] = ROTO_DIWSTOP;
    CopperList[Index++] = 0x0092;
    CopperList[Index++] = ROTO_DDFSTRT;
    CopperList[Index++] = 0x0094;
    CopperList[Index++] = ROTO_DDFSTOP;

    CopperList[Index++] = 0x0100;
    CopperList[Index++] = (UWORD)((HAM_DISPLAY_BPU << 12) | 0x0A00);
    CopperList[Index++] = 0x0102;
    CopperList[Index++] = 0x0000;
    CopperList[Index++] = 0x0104;
    CopperList[Index++] = 0x0000;

    CopperList[Index++] = 0x0108u;
    CopperList[Index++] = ROTO_REPEAT_MOD;
    CopperList[Index++] = 0x010A;
    CopperList[Index++] = ROTO_REPEAT_MOD;

    CopperList[Index++] = 0x0118;
    CopperList[Index++] = HAM_CONTROL_WORD_P5;
    CopperList[Index++] = 0x011A;
    CopperList[Index++] = HAM_CONTROL_WORD_P6;

    for (UWORD Plane = 0; Plane < NUMBEROFBITPLANES; ++Plane)
    {
        CopperList[Index++] = (UWORD)(0x00E0 + (Plane * 4));
        BPLPTH_Idx[Plane] = Index;
        CopperList[Index++] = 0x0000;

        CopperList[Index++] = (UWORD)(0x00E2 + (Plane * 4));
        BPLPTL_Idx[Plane] = Index;
        CopperList[Index++] = 0x0000;
    }

    for (UWORD c = 0; c < SCREEN_COLORS; ++c)
    {
        CopperList[Index++] = (UWORD)(0x0180 + (c * 2));
        CopperList[Index++] = DisplayPalette[c];
    }

    for (UWORD Line = 3; (Line + 1) < ROTO_DISPLAY_HEIGHT; Line += 4)
    {
        CopperList[Index++] = CopperWaitWord((UWORD)(ROTO_VPOS_START + Line));
        CopperList[Index++] = 0xFFFE;
        CopperList[Index++] = 0x0108;
        CopperList[Index++] = ROTO_ADVANCE_MOD;
        CopperList[Index++] = 0x010A;
        CopperList[Index++] = ROTO_ADVANCE_MOD;

        CopperList[Index++] = CopperWaitWord((UWORD)(ROTO_VPOS_START + Line + 1));
        CopperList[Index++] = 0xFFFE;
        CopperList[Index++] = 0x0108;
        CopperList[Index++] = ROTO_REPEAT_MOD;
        CopperList[Index++] = 0x010A;
        CopperList[Index++] = ROTO_REPEAT_MOD;
    }

    CopperList[Index++] = 0xFFFF;
    CopperList[Index++] = 0xFFFE;

    *COP1LC = (ULONG)CopperList;
}

inline static void Update_BitplanePointers(UBYTE Buffer)
{
    ULONG Ptr = (ULONG)ScreenBitmap[Buffer]->Planes[0] + ROTO_START_BYTE;

    for (UWORD Plane = 0; Plane < NUMBEROFBITPLANES; ++Plane)
    {
        CopperList[BPLPTH_Idx[Plane]] = (UWORD)(Ptr >> 16);
        CopperList[BPLPTL_Idx[Plane]] = (UWORD)(Ptr & 0xFFFF);
        Ptr += BYTESPERROW;
    }
}

// ---------------------------------------------------------------------
// Cleanup / main
// ---------------------------------------------------------------------

static void Cleanup_All(void)
{
    FreeMem(CopperList, CopperListSize);
    CopperList = NULL;

    FreeMem(TexturePacked, TexturePackedSize);
    TexturePacked = NULL;
    TexturePackedMid = NULL;

    FreeMem(DeltaTab, DeltaTabSize);
    DeltaTab = NULL;

    lwmf_CleanupScreenBitmaps();
    lwmf_CleanupAll();
}

int main(void)
{
    lwmf_LoadGraphicsLib();

    BuildMoveTable();
    BuildDeltaTable();
    InitTexture();
    lwmf_InitScreenBitmaps();
    Init_CopperList();

    lwmf_TakeOverOS();

    UBYTE DrawBuffer = 1;

    while (*CIAA_PRA & 0x40)
    {
        AnglePhase += 2;
        ++ZoomPhase;
        ++MovePhaseX;
        MovePhaseY += 2;

        DBG_COLOR(0x00F);
        RenderFrameAsm((UBYTE*)ScreenBitmap[DrawBuffer]->Planes[0] + ROTO_START_BYTE);
        DBG_COLOR(0x000);

        lwmf_WaitVertBlank();
        Update_BitplanePointers(DrawBuffer);

        DrawBuffer ^= 1;
    }

    Cleanup_All();
    return 0;
}