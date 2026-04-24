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

#define DEBUG 0

#if DEBUG
#define DBG_COLOR(c) (*COLOR00 = (c))
#else
#define DBG_COLOR(c) ((void)0)
#endif

// ---------------------------------------------------------------------
// Assembler interface
// ---------------------------------------------------------------------

typedef struct RotoAsmParams
{
    const UWORD* Texture;
    UBYTE*       Dest;
    const UWORD* Expand;
    WORD         RowU;
    WORD         RowV;
    WORD         DuDx;
    WORD         DvDx;
    WORD         DuDy;
    WORD         DvDy;
} RotoAsmParams;

extern void DrawRotoBodyAsm(__reg("a0") const struct RotoAsmParams* Params);

// ---------------------------------------------------------------------
// Effect constants
// ---------------------------------------------------------------------

#define TEXTURE_FILENAME        "gfx/128x128_ham.iff"
#define TEXTURE_SOURCE_WIDTH    128
#define TEXTURE_SOURCE_HEIGHT   128
#define TEXTURE_WIDTH           TEXTURE_SOURCE_WIDTH
#define TEXTURE_HEIGHT          TEXTURE_SOURCE_HEIGHT

#define HAM_DISPLAY_BPU         7
#define HAM_CONTROL_WORD_P5     0x7777u
#define HAM_CONTROL_WORD_P6     0xCCCCu
#define HAM_BACKGROUND_RGB4     0x000u

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
#define ROTO_MOD_SWITCH_COUNT   ((ROTO_ROWS - 1u) * 2u)

#define ROTO_VPOS_START         0x2Cu
#define ROTO_VPOS_STOP          (ROTO_VPOS_START + ROTO_DISPLAY_HEIGHT)
#define ROTO_DIWSTRT            (UWORD)(((ROTO_VPOS_START & 0xFFu) << 8) | 0x0081u)
#define ROTO_DIWSTOP            (UWORD)(((ROTO_VPOS_STOP  & 0xFFu) << 8) | 0x00C1u)
#define ROTO_DDFSTRT            0x0038u
#define ROTO_DDFSTOP            0x00D0u

#define SCREEN_COLORS           32
#define ROTO_ZOOM_BASE          384
#define ROTO_ZOOM_AMPLITUDE     128
#define ROTO_ZOOM_STEPS         32
#define ROTO_ANGLE_PHASE_STEP   2
#define ROTO_ANGLE_STEPS        (256 / ROTO_ANGLE_PHASE_STEP)
#define ROTO_DELTA_SCALE        3072L

#define HAM_EXPAND_COLORS       4096u
#define HAM_EXPAND_HI01_OFF     0u
#define HAM_EXPAND_LO01_OFF     (HAM_EXPAND_HI01_OFF + HAM_EXPAND_COLORS)
#define HAM_EXPAND_HI23_OFF     (HAM_EXPAND_LO01_OFF + HAM_EXPAND_COLORS)
#define HAM_EXPAND_LO23_OFF     (HAM_EXPAND_HI23_OFF + HAM_EXPAND_COLORS)
#define HAM_EXPAND_TOTAL_WORDS  (HAM_EXPAND_LO23_OFF + HAM_EXPAND_COLORS)
#define HAM_EXPAND_TOTAL_BYTES  ((ULONG)HAM_EXPAND_TOTAL_WORDS * sizeof(UWORD))

// ---------------------------------------------------------------------
// Delta table
// ---------------------------------------------------------------------

typedef struct
{
    WORD DuDx;
    WORD DvDx;
} RotoDelta;

static WORD       MoveTab[256];
static RotoDelta* DeltaTab = NULL;
static ULONG      DeltaTabSize = 0;

// ---------------------------------------------------------------------
// Sine table
// ---------------------------------------------------------------------

static const UBYTE SinTab256[256] =
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

static UWORD* TextureRGB12 = NULL;
static ULONG  TextureRGB12Size = 0;
static UWORD* HamExpand = NULL;
static UWORD  DisplayPalette[SCREEN_COLORS];

static UBYTE AnglePhase = 0;
static UBYTE ZoomPhase  = 0;
static UBYTE MovePhaseX = 0;
static UBYTE MovePhaseY = 64;

// ---------------------------------------------------------------------
// Copper list
// ---------------------------------------------------------------------

static UWORD* CopperList = NULL;
static ULONG  CopperListSize = 0;

static UWORD BPLPTH_Idx[NUMBEROFBITPLANES];
static UWORD BPLPTL_Idx[NUMBEROFBITPLANES];

// ---------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------

static UWORD CopperWaitWord(UWORD VPos)
{
    return (UWORD)(((VPos & 0xFFu) << 8) | 0x0001u);
}

static UBYTE GetPlanarPixel(const struct BitMap* BitMap, UWORD X, UWORD Y, UBYTE Depth)
{
    const ULONG RowOffset = (ULONG)Y * (ULONG)BitMap->BytesPerRow;
    const ULONG ByteOffset = RowOffset + (ULONG)(X >> 3);
    const UBYTE Mask = (UBYTE)(0x80u >> (X & 7u));
    UBYTE Pixel = 0;

    for (UBYTE Plane = 0; Plane < Depth; ++Plane)
    {
        const UBYTE* PlaneBase = (const UBYTE*)BitMap->Planes[Plane];

        if (PlaneBase[ByteOffset] & Mask)
        {
            Pixel |= (UBYTE)(1u << Plane);
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

static BOOL BuildDeltaTable(void)
{
    DeltaTabSize = (ULONG)ROTO_ZOOM_STEPS * (ULONG)ROTO_ANGLE_STEPS * sizeof(RotoDelta);
    DeltaTab = (RotoDelta*)lwmf_AllocCpuMem(DeltaTabSize, MEMF_CLEAR);

    if (!DeltaTab)
    {
        PutStr("Not enough memory for delta table.\n");
        return FALSE;
    }

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

    return TRUE;
}

static BOOL BuildHamExpandTable(void)
{
    HamExpand = (UWORD*)lwmf_AllocCpuMem(HAM_EXPAND_TOTAL_BYTES, MEMF_CLEAR);

    if (!HamExpand)
    {
        PutStr("Not enough memory for HAM expand table.\n");
        return FALSE;
    }

    for (UWORD Color = 0; Color < HAM_EXPAND_COLORS; ++Color)
    {
        const UBYTE R = (UBYTE)((Color >> 8) & 0x0Fu);
        const UBYTE G = (UBYTE)((Color >> 4) & 0x0Fu);
        const UBYTE B = (UBYTE)( Color       & 0x0Fu);

        UBYTE PlaneNibble[4];

        for (UBYTE Plane = 0; Plane < 4; ++Plane)
        {
            const UBYTE BitR = (UBYTE)((R >> Plane) & 1u);
            const UBYTE BitG = (UBYTE)((G >> Plane) & 1u);
            const UBYTE BitB = (UBYTE)((B >> Plane) & 1u);

            PlaneNibble[Plane] = (UBYTE)((BitR << 3) | (BitG << 2) | (BitB << 1) | BitB);
        }

        HamExpand[HAM_EXPAND_HI01_OFF + Color] =
            (UWORD)((PlaneNibble[1] << 12) | (PlaneNibble[0] << 4));
        HamExpand[HAM_EXPAND_LO01_OFF + Color] =
            (UWORD)((PlaneNibble[1] <<  8) |  PlaneNibble[0]);
        HamExpand[HAM_EXPAND_HI23_OFF + Color] =
            (UWORD)((PlaneNibble[3] << 12) | (PlaneNibble[2] << 4));
        HamExpand[HAM_EXPAND_LO23_OFF + Color] =
            (UWORD)((PlaneNibble[3] <<  8) |  PlaneNibble[2]);
    }

    return TRUE;
}

static void BuildDisplayPalette(const struct lwmf_Image* Image)
{
    for (UWORD i = 0; i < SCREEN_COLORS; ++i)
    {
        DisplayPalette[i] = 0x000u;
    }

    DisplayPalette[0] = HAM_BACKGROUND_RGB4;

    if (Image->CRegs)
    {
        const UWORD Limit = (Image->NumberOfColors < 16u) ? Image->NumberOfColors : 16u;

        for (UWORD i = 1; i < Limit; ++i)
        {
            DisplayPalette[i] = (UWORD)(Image->CRegs[i] & 0x0FFFu);
        }
    }
}

static BOOL BuildTextureFromHAM(const struct lwmf_Image* Image)
{
    UWORD BasePal[16];

    for (UWORD i = 0; i < 16; ++i)
    {
        BasePal[i] = 0x000u;
    }

    if (Image->CRegs)
    {
        const UWORD Limit = (Image->NumberOfColors < 16u) ? Image->NumberOfColors : 16u;

        for (UWORD i = 0; i < Limit; ++i)
        {
            BasePal[i] = (UWORD)(Image->CRegs[i] & 0x0FFFu);
        }
    }

    TextureRGB12Size = (ULONG)TEXTURE_WIDTH * (ULONG)TEXTURE_HEIGHT * sizeof(UWORD);
    TextureRGB12 = (UWORD*)lwmf_AllocCpuMem(TextureRGB12Size, MEMF_CLEAR);

    if (!TextureRGB12)
    {
        PutStr("Not enough memory for HAM texture.\n");
        return FALSE;
    }

    for (UWORD Y = 0; Y < TEXTURE_SOURCE_HEIGHT; ++Y)
    {
        UWORD CurrentRGB = BasePal[0];

        for (UWORD X = 0; X < TEXTURE_SOURCE_WIDTH; ++X)
        {
            const UBYTE Pixel = GetPlanarPixel(&Image->Image, X, Y, Image->Image.Depth);
            const UBYTE Data  = (UBYTE)(Pixel & 0x0Fu);
            const UBYTE Ctrl  = (UBYTE)(Pixel >> 4);
            UWORD OutRGB;

            switch (Ctrl)
            {
                case 0:
                    OutRGB = BasePal[Data & 0x0Fu];
                    break;

                case 1:
                    OutRGB = (UWORD)((CurrentRGB & 0x0FF0u) | Data);
                    break;

                case 2:
                    OutRGB = (UWORD)((CurrentRGB & 0x00FFu) | ((UWORD)Data << 8));
                    break;

                default:
                    OutRGB = (UWORD)((CurrentRGB & 0x0F0Fu) | ((UWORD)Data << 4));
                    break;
            }

            CurrentRGB = OutRGB;
            TextureRGB12[(ULONG)Y * TEXTURE_WIDTH + X] = OutRGB;
        }
    }

    return TRUE;
}

static BOOL BuildTextureFromIndexed(const struct lwmf_Image* Image)
{
    UWORD BasePal[16];

    for (UWORD i = 0; i < 16; ++i)
    {
        BasePal[i] = (UWORD)((i << 8) | (i << 4) | i);
    }

    if (Image->CRegs)
    {
        const UWORD Limit = (Image->NumberOfColors < 16u) ? Image->NumberOfColors : 16u;

        for (UWORD i = 0; i < Limit; ++i)
        {
            BasePal[i] = (UWORD)(Image->CRegs[i] & 0x0FFFu);
        }
    }

    TextureRGB12Size = (ULONG)TEXTURE_WIDTH * (ULONG)TEXTURE_HEIGHT * sizeof(UWORD);
    TextureRGB12 = (UWORD*)lwmf_AllocCpuMem(TextureRGB12Size, MEMF_CLEAR);

    if (!TextureRGB12)
    {
        PutStr("Not enough memory for texture.\n");
        return FALSE;
    }

    for (UWORD Y = 0; Y < TEXTURE_SOURCE_HEIGHT; ++Y)
    {
        for (UWORD X = 0; X < TEXTURE_SOURCE_WIDTH; ++X)
        {
            const UBYTE Pixel = GetPlanarPixel(&Image->Image, X, Y, Image->Image.Depth);
            const UWORD RGB12 = BasePal[Pixel & 0x0Fu];

            TextureRGB12[(ULONG)Y * TEXTURE_WIDTH + X] = RGB12;
        }
    }

    return TRUE;
}

static BOOL InitTexture(void)
{
    struct lwmf_Image* Image = lwmf_LoadImage(TEXTURE_FILENAME);

    if (!Image)
    {
        return FALSE;
    }

    BuildDisplayPalette(Image);

    if (Image->Image.Depth == 6u)
    {
        if (!BuildTextureFromHAM(Image))
        {
            lwmf_DeleteImage(Image);
            return FALSE;
        }
    }
    else
    {
        if (!BuildTextureFromIndexed(Image))
        {
            lwmf_DeleteImage(Image);
            return FALSE;
        }
    }

    lwmf_DeleteImage(Image);
    return TRUE;
}

static BOOL Init_CopperList(void)
{
    const ULONG CopperWords =
        24u +
        (4u * NUMBEROFBITPLANES) +
        (SCREEN_COLORS * 2u) +
        (ROTO_MOD_SWITCH_COUNT * 6u) +
        2u;

    CopperListSize = CopperWords * sizeof(UWORD);
    CopperList = (UWORD*)AllocMem(CopperListSize, MEMF_CHIP | MEMF_CLEAR);

    if (!CopperList)
    {
        PutStr("Not enough Chip RAM for copper list.\n");
        return FALSE;
    }

    UWORD Index = 0;

    CopperList[Index++] = 0x008Eu;
    CopperList[Index++] = ROTO_DIWSTRT;
    CopperList[Index++] = 0x0090u;
    CopperList[Index++] = ROTO_DIWSTOP;
    CopperList[Index++] = 0x0092u;
    CopperList[Index++] = ROTO_DDFSTRT;
    CopperList[Index++] = 0x0094u;
    CopperList[Index++] = ROTO_DDFSTOP;

    CopperList[Index++] = 0x0100u;
    CopperList[Index++] = (UWORD)((HAM_DISPLAY_BPU << 12) | 0x0A00u);
    CopperList[Index++] = 0x0102u;
    CopperList[Index++] = 0x0000u;
    CopperList[Index++] = 0x0104u;
    CopperList[Index++] = 0x0000u;

    CopperList[Index++] = 0x0108u;
    CopperList[Index++] = ROTO_REPEAT_MOD;
    CopperList[Index++] = 0x010Au;
    CopperList[Index++] = ROTO_REPEAT_MOD;

    CopperList[Index++] = 0x0118u;
    CopperList[Index++] = HAM_CONTROL_WORD_P5;
    CopperList[Index++] = 0x011Au;
    CopperList[Index++] = HAM_CONTROL_WORD_P6;

    for (UWORD Plane = 0; Plane < NUMBEROFBITPLANES; ++Plane)
    {
        CopperList[Index++] = (UWORD)(0x00E0u + (Plane * 4u));
        BPLPTH_Idx[Plane] = Index;
        CopperList[Index++] = 0x0000u;

        CopperList[Index++] = (UWORD)(0x00E2u + (Plane * 4u));
        BPLPTL_Idx[Plane] = Index;
        CopperList[Index++] = 0x0000u;
    }

    for (UWORD c = 0; c < SCREEN_COLORS; ++c)
    {
        CopperList[Index++] = (UWORD)(0x0180u + (c * 2u));
        CopperList[Index++] = DisplayPalette[c];
    }

    for (UWORD Line = 3; (Line + 1u) < ROTO_DISPLAY_HEIGHT; Line += 4)
    {
        CopperList[Index++] = CopperWaitWord((UWORD)(ROTO_VPOS_START + Line));
        CopperList[Index++] = 0xFFFEu;
        CopperList[Index++] = 0x0108u;
        CopperList[Index++] = ROTO_ADVANCE_MOD;
        CopperList[Index++] = 0x010Au;
        CopperList[Index++] = ROTO_ADVANCE_MOD;

        CopperList[Index++] = CopperWaitWord((UWORD)(ROTO_VPOS_START + Line + 1u));
        CopperList[Index++] = 0xFFFEu;
        CopperList[Index++] = 0x0108u;
        CopperList[Index++] = ROTO_REPEAT_MOD;
        CopperList[Index++] = 0x010Au;
        CopperList[Index++] = ROTO_REPEAT_MOD;
    }

    CopperList[Index++] = 0xFFFFu;
    CopperList[Index++] = 0xFFFEu;

    *COP1LC = (ULONG)CopperList;
    return TRUE;
}

static void Update_BitplanePointers(UBYTE Buffer)
{
    ULONG Ptr = (ULONG)ScreenBitmap[Buffer]->Planes[0] + ROTO_START_BYTE;

    for (UWORD Plane = 0; Plane < NUMBEROFBITPLANES; ++Plane)
    {
        CopperList[BPLPTH_Idx[Plane]] = (UWORD)(Ptr >> 16);
        CopperList[BPLPTL_Idx[Plane]] = (UWORD)(Ptr & 0xFFFFu);
        Ptr += BYTESPERROW;
    }
}

static void AdvanceAnimation(void)
{
    AnglePhase = (UBYTE)(AnglePhase + 2u);
    ZoomPhase  = (UBYTE)(ZoomPhase  + 1u);
    MovePhaseX = (UBYTE)(MovePhaseX + 1u);
    MovePhaseY = (UBYTE)(MovePhaseY + 2u);
}

static void RenderFrame(UBYTE Buffer)
{
    const UWORD AngleIndex = (UWORD)(AnglePhase / ROTO_ANGLE_PHASE_STEP);
    const UWORD ZoomIndex  = (UWORD)(((UWORD)SinTab256[ZoomPhase] * (ROTO_ZOOM_STEPS - 1u)) / 63u);
    const RotoDelta* Delta = &DeltaTab[(ULONG)ZoomIndex * ROTO_ANGLE_STEPS + AngleIndex];

    const WORD DuDx = Delta->DuDx;
    const WORD DvDx = Delta->DvDx;
    const WORD DuDy = (WORD)(-DvDx);
    const WORD DvDy = DuDx;

    const LONG CenterU = (LONG)(TEXTURE_WIDTH  / 2) << 8;
    const LONG CenterV = (LONG)(TEXTURE_HEIGHT / 2) << 8;

    RotoAsmParams Params;

    Params.Texture = TextureRGB12;
    Params.Dest    = (UBYTE*)ScreenBitmap[Buffer]->Planes[0] + ROTO_START_BYTE;
    Params.Expand  = HamExpand;
    Params.RowU    = (WORD)(CenterU + MoveTab[MovePhaseX] - ((LONG)ROTO_HALF_COLUMNS * DuDx) - ((LONG)ROTO_HALF_ROWS * DuDy));
    Params.RowV    = (WORD)(CenterV + MoveTab[MovePhaseY] - ((LONG)ROTO_HALF_COLUMNS * DvDx) - ((LONG)ROTO_HALF_ROWS * DvDy));
    Params.DuDx    = DuDx;
    Params.DvDx    = DvDx;
    Params.DuDy    = DuDy;
    Params.DvDy    = DvDy;

    DrawRotoBodyAsm(&Params);
}

// ---------------------------------------------------------------------
// Cleanup / main
// ---------------------------------------------------------------------

static void Cleanup_All(void)
{
    if (CopperList)
    {
        FreeMem(CopperList, CopperListSize);
        CopperList = NULL;
        CopperListSize = 0;
    }

    if (TextureRGB12)
    {
        FreeMem(TextureRGB12, TextureRGB12Size);
        TextureRGB12 = NULL;
        TextureRGB12Size = 0;
    }

    if (HamExpand)
    {
        FreeMem(HamExpand, HAM_EXPAND_TOTAL_BYTES);
        HamExpand = NULL;
    }

    if (DeltaTab)
    {
        FreeMem(DeltaTab, DeltaTabSize);
        DeltaTab = NULL;
        DeltaTabSize = 0;
    }

    lwmf_CleanupScreenBitmaps();
    lwmf_CleanupAll();
}

int main(void)
{
    if (lwmf_LoadGraphicsLib())
    {
        return 20;
    }

    BuildMoveTable();

    if (!BuildDeltaTable() ||
        !BuildHamExpandTable() ||
        !InitTexture() ||
        !lwmf_InitScreenBitmaps() ||
        !Init_CopperList())
    {
        Cleanup_All();
        return 20;
    }

    lwmf_TakeOverOS();

    UBYTE ViewBuffer = 0;
    UBYTE DrawBuffer = 1;

    RenderFrame(ViewBuffer);
    Update_BitplanePointers(ViewBuffer);

    while (*CIAA_PRA & 0x40)
    {
        DBG_COLOR(0x00Fu);
        AdvanceAnimation();
        RenderFrame(DrawBuffer);
        DBG_COLOR(0x000u);

        lwmf_WaitVertBlank();
        Update_BitplanePointers(DrawBuffer);

        ViewBuffer ^= 1u;
        DrawBuffer ^= 1u;
    }

    Cleanup_All();
    return 0;
}
