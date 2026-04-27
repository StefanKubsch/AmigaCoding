//**********************************************************************
//* 4x4 HAM7 Rotozoomer                                                *
//*                                                                    *
//* 4 DMA bitplanes, HAM control via BPL5DAT/BPL6DAT, 28 columns      *
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

extern void RenderFrameAsm(__reg("a0") UBYTE* Dest, __reg("a1") const void* FrameState);
extern void RenderFastB0Entry(void);
extern void RenderFastBp1Entry(void);
extern void RenderFastBm1Entry(void);
extern void RenderFastBm2Entry(void);

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
#define ROTO_COLUMNS            28
#define ROTO_ROWS               48
#define ROTO_PAIR_COUNT         (ROTO_COLUMNS / 2)
#define ROTO_DISPLAY_WIDTH      (ROTO_COLUMNS * CHUNKY_PIXEL_SIZE)
#define ROTO_DISPLAY_HEIGHT     (ROTO_ROWS * CHUNKY_PIXEL_SIZE)
#define ROTO_HALF_COLUMNS       (ROTO_COLUMNS / 2)
#define ROTO_HALF_ROWS          (ROTO_ROWS / 2)

#define ROTO_SCREEN_WIDTH       320
#define ROTO_SCREEN_HEIGHT      256
#define ROTO_START_X            ((ROTO_SCREEN_WIDTH - ROTO_DISPLAY_WIDTH) / 2)
#define ROTO_DDF_SHIFT_BYTES    (ROTO_START_X >> 3)
#define ROTO_FETCH_BYTES        (ROTO_DISPLAY_WIDTH >> 3)
#define ROTO_PLANE_STRIDE       ROTO_FETCH_BYTES
#define ROTO_PLANE_BYTES        ((UWORD)(ROTO_PLANE_STRIDE * ROTO_ROWS))
#define ROTO_VISIBLE_BYTES      ((ULONG)ROTO_PLANE_BYTES * NUMBEROFBITPLANES)
#define ROTO_REPEAT_MOD         ((UWORD)(-(WORD)ROTO_FETCH_BYTES))
#define ROTO_ADVANCE_MOD        ((UWORD)0)
#define ROTO_MOD_SWITCH_COUNT   ((ROTO_ROWS - 1) * 2)

#define ROTO_PAL_VPOS_TOP       0x2C
#define ROTO_VPOS_START         (ROTO_PAL_VPOS_TOP + ((ROTO_SCREEN_HEIGHT - ROTO_DISPLAY_HEIGHT) / 2))
#define ROTO_VPOS_STOP          (ROTO_VPOS_START + ROTO_DISPLAY_HEIGHT)
#define ROTO_DIWSTRT            (UWORD)(((ROTO_VPOS_START & 0xFF) << 8) | 0x0081)
#define ROTO_DIWSTOP            (UWORD)(((ROTO_VPOS_STOP  & 0xFF) << 8) | 0x00C1)

// Center the playfield inside the normal 320-pixel lowres window
// by shrinking the data fetch symmetrically on both sides. In lowres, one
// byte (8 pixels) corresponds to a DDF delta of 0x04.
#define ROTO_DDFSTRT            (0x0038 + (ROTO_DDF_SHIFT_BYTES * 4))
#define ROTO_DDFSTOP            (0x00D0 - (ROTO_DDF_SHIFT_BYTES * 4))

#define SCREEN_COLORS           32
#define ROTO_ZOOM_BASE          384
#define ROTO_ZOOM_AMPLITUDE     128
#define ROTO_ZOOM_STEPS         32
#define ROTO_ANGLE_PHASE_STEP   2
#define ROTO_ANGLE_STEPS        (256 / ROTO_ANGLE_PHASE_STEP)
#define ROTO_DELTA_SCALE        3072
#define ROTO_CENTER_U           0x4000
#define ROTO_CENTER_V           0x4000

// ---------------------------------------------------------------------
// Precomputed frame + row state tables
// ---------------------------------------------------------------------

typedef struct
{
    UWORD NextUc;
    UWORD NextRow;
    UWORD PackedBytes;
    ULONG PackedPairs[3];
} RotoRowState;

typedef struct
{
    WORD         DuC;
    UBYTE        DuL;
    UBYTE        DvRem;
    void       (*Entry)(void);
    RotoRowState Rows[ROTO_ROWS];
} RotoFrameBlock;

typedef char RotoRowStateSizeMustBe18[(sizeof(RotoRowState) == 18) ? 1 : -1];
typedef char RotoFrameBlockSizeMustBe872[(sizeof(RotoFrameBlock) == 872) ? 1 : -1];

enum
{
    ROTO_FAMILY_B0 = 0,
    ROTO_FAMILY_BP1,
    ROTO_FAMILY_BM1,
    ROTO_FAMILY_BM2
};

RotoFrameBlock* FrameBlocks = NULL;
static ULONG FrameBlocksSize = 0;
RotoFrameBlock* CurrentFrameBlock = NULL;
static RotoFrameBlock* FrameBlocksEnd = NULL;

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

// TexturePackedHi contains the high-nibble contribution for texel 0 in a pair.
// TexturePackedLo contains the pre-shifted low-nibble contribution for texel 1.
// Both tables live in one CPU-only allocation so the hotloop can drop a 68000 long-word shift per PROCESS_PAIR.
static UBYTE* TexturePackedBlock = NULL;
static UBYTE* TexturePackedHi = NULL;
static UBYTE* TexturePackedLo = NULL;
ULONG* TexturePackedMidHi = NULL;
ULONG* TexturePackedMidLo = NULL;
static ULONG TexturePackedSize = 0;
static UWORD DisplayPalette[SCREEN_COLORS];
static UBYTE* RotoBuffers[2] = { NULL, NULL };

// CurrentFrameBlock is seeded after BuildFrameStates() so the
// first rendered image still matches the former phase-updated-before-render
// sequence. BuildFrameStates now also folds the exact first three pairs of every row
// into the row seed, so InitTexture() must have run first.

// ---------------------------------------------------------------------
// Rotozoomer
// ---------------------------------------------------------------------

static const ULONG HamPackedR[16] =
{
    0x00000000UL, 0x00000080UL, 0x00008000UL, 0x00008080UL,
    0x00800000UL, 0x00800080UL, 0x00808000UL, 0x00808080UL,
    0x80000000UL, 0x80000080UL, 0x80008000UL, 0x80008080UL,
    0x80800000UL, 0x80800080UL, 0x80808000UL, 0x80808080UL
};

static const ULONG HamPackedG[16] =
{
    0x00000000UL, 0x00000040UL, 0x00004000UL, 0x00004040UL,
    0x00400000UL, 0x00400040UL, 0x00404000UL, 0x00404040UL,
    0x40000000UL, 0x40000040UL, 0x40004000UL, 0x40004040UL,
    0x40400000UL, 0x40400040UL, 0x40404000UL, 0x40404040UL
};

static const ULONG HamPackedB[16] =
{
    0x00000000UL, 0x00000030UL, 0x00003000UL, 0x00003030UL,
    0x00300000UL, 0x00300030UL, 0x00303000UL, 0x00303030UL,
    0x30000000UL, 0x30000030UL, 0x30003000UL, 0x30003030UL,
    0x30300000UL, 0x30300030UL, 0x30303000UL, 0x30303030UL
};

static const UBYTE ZeroPlaneRow[TEXTURE_SOURCE_WIDTH / 8] = { 0 };

static WORD Asr6Word(WORD Value)
{
    LONG Temp = (LONG)Value;

    if (Temp < 0)
    {
        Temp = -(((-Temp) + 63L) >> 6);
    }
    else
    {
        Temp >>= 6;
    }

    return (WORD)Temp;
}

static WORD Asr1Word(WORD Value)
{
    LONG Temp = (LONG)Value;

    if (Temp < 0)
    {
        Temp = -(((-Temp) + 1L) >> 1);
    }
    else
    {
        Temp >>= 1;
    }

    return (WORD)Temp;
}

static WORD Low6Quad(WORD Value)
{
    return (WORD)((((UWORD)Value) & 0x003F) << 2);
}

static void BuildFrameStates(void)
{
    // The shipped effect only ever walks one fixed 256-frame cycle. Build the
    // exact hotloop seed for each frame and each rendered row once so the
    // assembler can skip both frame setup and the once-per-row state rebuild.
    //
    // The earlier version replayed all 48 horizontal samples for every row in
    // C. That was exact, but very slow on 68000. The split-U and cached-V
    // states can be merged into linear combined states:
    //
    //   UState = [Uc:16 | Ul:8]
    //   WState = [(Row>>1)&$FF00 | WLow]
    //
    // Both evolve modulo 24 / 16 bits, so one exact row advance replaces the
    // whole inner pair simulation during init.
    FrameBlocksSize = 256UL * (ULONG)sizeof(RotoFrameBlock);

    FrameBlocks = (RotoFrameBlock*)lwmf_AllocCpuMem(FrameBlocksSize, MEMF_CLEAR);

    for (UWORD Frame = 0; Frame < 256; ++Frame)
    {
        const UBYTE AnglePhase = (UBYTE)(Frame * ROTO_ANGLE_PHASE_STEP);
        const UBYTE ZoomPhase = (UBYTE)Frame;
        const UBYTE MovePhaseX = (UBYTE)Frame;
        const UBYTE MovePhaseY = (UBYTE)(64 + (Frame * 2));
        const LONG ZoomIndex = (LONG)(((ULONG)SinTab256[ZoomPhase] * 31UL) / 63UL);
        const LONG Zoom =
            (LONG)ROTO_ZOOM_BASE -
            (LONG)ROTO_ZOOM_AMPLITUDE +
            ((ZoomIndex * ((LONG)ROTO_ZOOM_AMPLITUDE * 2L)) / (LONG)(ROTO_ZOOM_STEPS - 1));
        const LONG SinV = (LONG)((WORD)SinTab256[AnglePhase] - 32);
        const LONG CosV = (LONG)((WORD)SinTab256[(UBYTE)(AnglePhase + 64)] - 32);
        const WORD DuDx = (WORD)((CosV * ROTO_DELTA_SCALE) / Zoom);
        const WORD DvDx = (WORD)((SinV * ROTO_DELTA_SCALE) / Zoom);
        const WORD StartUOffset =
            (WORD)(-((LONG)ROTO_HALF_COLUMNS * (LONG)DuDx) +
                   ((LONG)ROTO_HALF_ROWS * (LONG)DvDx));
        const WORD StartVOffset =
            (WORD)(-((LONG)ROTO_HALF_COLUMNS * (LONG)DvDx) -
                   ((LONG)ROTO_HALF_ROWS * (LONG)DuDx));
        const WORD RowStepU = (WORD)(-((LONG)DvDx + ((LONG)ROTO_COLUMNS * (LONG)DuDx)));
        const WORD StartUcOffset = (WORD)(((UWORD)StartUOffset) >> 6);
        const WORD StartVTransOffset = (WORD)(2L * (LONG)StartVOffset);
        const WORD RowStepUc = Asr6Word(RowStepU);
        const WORD StartUl = Low6Quad(StartUOffset);
        const WORD DuC = Asr6Word(DuDx);
        const WORD RowStepUl = Low6Quad(RowStepU);
        const WORD DuL = Low6Quad(DuDx);
        const WORD RowStepVTrans = (WORD)(2L * ((LONG)DuDx - ((LONG)ROTO_COLUMNS * (LONG)DvDx)));
        const WORD RowStepV = Asr1Word(RowStepVTrans);
        const WORD MoveX = (WORD)(((WORD)SinTab256[MovePhaseX] - 32) << 8);
        const WORD MoveY = (WORD)(((WORD)SinTab256[MovePhaseY] - 32) << 8);
        const UWORD MoveUcBase = (UWORD)(((UWORD)((WORD)ROTO_CENTER_U + MoveX)) >> 6);
        const WORD StartUc = (WORD)(((WORD)MoveUcBase + StartUcOffset) & 0x03FF);
        const UWORD BaseV = (UWORD)((WORD)ROTO_CENTER_V + MoveY);
        const WORD StartVTrans =
            (WORD)((WORD)((((ULONG)BaseV) << 1) ^ 0x8000UL) + StartVTransOffset);
        const UWORD DuCWord = (UWORD)DuC;
        const UBYTE DuLByte = (UBYTE)DuL;
        const ULONG USampleAdvance = ((((ULONG)DuCWord) << 8) | (ULONG)DuLByte) & 0x00FFFFFFUL;
        const UWORD RowStepUcWord = (UWORD)RowStepUc;
        const UBYTE RowStepUlByte = (UBYTE)RowStepUl;
        const UWORD RowStepVWord = (UWORD)RowStepV;
        const UBYTE DvRem = (UBYTE)DvDx;
        ULONG UState = (((ULONG)(UWORD)StartUc) << 8) | (ULONG)(UBYTE)StartUl;
        UWORD WState = (UWORD)(((UWORD)StartVTrans >> 1) & 0xFFFFU);
        ULONG URowAdvance;
        UWORD VSampleStep = 0;
        UWORD WRowAdvance;
        UWORD Family = ROTO_FAMILY_B0;
        RotoFrameBlock* State = &FrameBlocks[Frame];
        RotoRowState* FrameRows = State->Rows;

        if (DvDx < 0)
        {
            Family = (DvDx < -256) ? ROTO_FAMILY_BM2 : ROTO_FAMILY_BM1;
        }
        else if (DvDx > 255)
        {
            Family = ROTO_FAMILY_BP1;
        }        State->DuC = DuC;
        State->DuL = DuLByte;
        State->DvRem = DvRem;

        if (Family == ROTO_FAMILY_B0)
        {
            State->Entry = RenderFastB0Entry;
            VSampleStep = (UWORD)DvRem;
        }
        else if (Family == ROTO_FAMILY_BM1)
        {
            State->Entry = RenderFastBm1Entry;
            VSampleStep = (UWORD)(0xFF00U | (UWORD)DvRem);
        }
        else if (Family == ROTO_FAMILY_BM2)
        {
            State->Entry = RenderFastBm2Entry;
            VSampleStep = (UWORD)(0xFE00U | (UWORD)DvRem);
        }
        else
        {
            State->Entry = RenderFastBp1Entry;
            VSampleStep = (UWORD)(0x0100U | (UWORD)DvRem);
        }

        URowAdvance =
            (((ULONG)ROTO_COLUMNS * ((((ULONG)DuCWord) << 8) | (ULONG)DuLByte)) +
             ((((ULONG)RowStepUcWord) << 8) | (ULONG)RowStepUlByte)) & 0x00FFFFFFUL;
        WRowAdvance =
            (UWORD)(((ULONG)ROTO_COLUMNS * (ULONG)VSampleStep + (ULONG)RowStepVWord) & 0xFFFFUL);

        for (UWORD Row = 0; Row < ROTO_ROWS; ++Row)
        {
            RotoRowState* RowSeed = &FrameRows[Row];
            const ULONG UState0 = UState;
            const UWORD WState0 = WState;
            const UWORD StartUc0 = (UWORD)(((UWORD)(UState0 >> 8)) & 0x01FFU);
            const UWORD StartRow0 = (UWORD)((WState0 << 1) & 0xFE00U);
            const UWORD StartOffset0 =
                (UWORD)((StartRow0 + (UWORD)(StartUc0 & 0x01FCU)) & 0xFFFFU);

            const ULONG UState1 = (UState0 + USampleAdvance) & 0x00FFFFFFUL;
            const UWORD WState1 = (UWORD)((WState0 + VSampleStep) & 0xFFFFU);
            const UWORD StartUc1 = (UWORD)(((UWORD)(UState1 >> 8)) & 0x01FFU);
            const UWORD StartRow1 = (UWORD)((WState1 << 1) & 0xFE00U);
            const UWORD StartOffset1 =
                (UWORD)((StartRow1 + (UWORD)(StartUc1 & 0x01FCU)) & 0xFFFFU);

            const ULONG UState2 = (UState1 + USampleAdvance) & 0x00FFFFFFUL;
            const UWORD WState2 = (UWORD)((WState1 + VSampleStep) & 0xFFFFU);
            const UWORD StartUc2 = (UWORD)(((UWORD)(UState2 >> 8)) & 0x01FFU);
            const UWORD StartRow2 = (UWORD)((WState2 << 1) & 0xFE00U);
            const UWORD StartOffset2 =
                (UWORD)((StartRow2 + (UWORD)(StartUc2 & 0x01FCU)) & 0xFFFFU);

            const ULONG UState3 = (UState2 + USampleAdvance) & 0x00FFFFFFUL;
            const UWORD WState3 = (UWORD)((WState2 + VSampleStep) & 0xFFFFU);
            const UWORD StartUc3 = (UWORD)(((UWORD)(UState3 >> 8)) & 0x01FFU);
            const UWORD StartRow3 = (UWORD)((WState3 << 1) & 0xFE00U);
            const UWORD StartOffset3 =
                (UWORD)((StartRow3 + (UWORD)(StartUc3 & 0x01FCU)) & 0xFFFFU);

            const ULONG UState4 = (UState3 + USampleAdvance) & 0x00FFFFFFUL;
            const UWORD WState4 = (UWORD)((WState3 + VSampleStep) & 0xFFFFU);
            const UWORD StartUc4 = (UWORD)(((UWORD)(UState4 >> 8)) & 0x01FFU);
            const UWORD StartRow4 = (UWORD)((WState4 << 1) & 0xFE00U);
            const UWORD StartOffset4 =
                (UWORD)((StartRow4 + (UWORD)(StartUc4 & 0x01FCU)) & 0xFFFFU);

            const ULONG UState5 = (UState4 + USampleAdvance) & 0x00FFFFFFUL;
            const UWORD WState5 = (UWORD)((WState4 + VSampleStep) & 0xFFFFU);
            const UWORD StartUc5 = (UWORD)(((UWORD)(UState5 >> 8)) & 0x01FFU);
            const UWORD StartRow5 = (UWORD)((WState5 << 1) & 0xFE00U);
            const UWORD StartOffset5 =
                (UWORD)((StartRow5 + (UWORD)(StartUc5 & 0x01FCU)) & 0xFFFFU);

            const ULONG UState6 = (UState5 + USampleAdvance) & 0x00FFFFFFUL;
            const UWORD WState6 = (UWORD)((WState5 + VSampleStep) & 0xFFFFU);

            RowSeed->NextUc =
                (UWORD)(((UWORD)(UState6 >> 8)) & 0x01FFU);
            RowSeed->NextRow =
                (UWORD)((WState6 << 1) & 0xFE00U);
            RowSeed->PackedBytes =
                (UWORD)((((UWORD)WState6 & 0x00FFU) << 8) | (UWORD)(UState6 & 0x00FFUL));
            RowSeed->PackedPairs[0] =
                (*(const ULONG*)((const UBYTE*)TexturePackedMidHi + (WORD)StartOffset0)) |
                (*(const ULONG*)((const UBYTE*)TexturePackedMidLo + (WORD)StartOffset1));
            RowSeed->PackedPairs[1] =
                (*(const ULONG*)((const UBYTE*)TexturePackedMidHi + (WORD)StartOffset2)) |
                (*(const ULONG*)((const UBYTE*)TexturePackedMidLo + (WORD)StartOffset3));
            RowSeed->PackedPairs[2] =
                (*(const ULONG*)((const UBYTE*)TexturePackedMidHi + (WORD)StartOffset4)) |
                (*(const ULONG*)((const UBYTE*)TexturePackedMidLo + (WORD)StartOffset5));

            UState = (UState + URowAdvance) & 0x00FFFFFFUL;
            WState = (UWORD)((WState + WRowAdvance) & 0xFFFFU);
        }
    }
}

static ULONG PackHamContributionHi(UWORD Color)
{
    return
        HamPackedR[(Color >> 8) & 0x0F] |
        HamPackedG[(Color >> 4) & 0x0F] |
        HamPackedB[Color & 0x0F];
}

static void AllocTexturePacked(void)
{
    TexturePackedSize = TEXTURE_PACKED_TOTAL_BYTES * 2UL;
    TexturePackedBlock = (UBYTE*)lwmf_AllocCpuMem(TexturePackedSize, MEMF_CLEAR);
    TexturePackedHi = TexturePackedBlock;
    TexturePackedLo = TexturePackedBlock + TEXTURE_PACKED_TOTAL_BYTES;
    TexturePackedMidHi = (ULONG*)(TexturePackedHi + TEXTURE_PACKED_CENTER);
    TexturePackedMidLo = (ULONG*)(TexturePackedLo + TEXTURE_PACKED_CENTER);
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
    UWORD BasePal[16] = { 0 };
    const UBYTE Depth = Image->Image.Depth;
    const UWORD ByteColumns = (TEXTURE_SOURCE_WIDTH / 8);
    const ULONG ImageRowBytes = (ULONG)Image->Image.BytesPerRow;
    const UWORD Limit = (Image->NumberOfColors < 16) ? Image->NumberOfColors : 16;

    for (UWORD i = 0; i < Limit; ++i)
    {
        BasePal[i] = (UWORD)(Image->CRegs[i] & 0x0FFF);
    }

    for (UWORD Y = 0; Y < TEXTURE_SOURCE_HEIGHT; ++Y)
    {
        const ULONG PlaneRowOffset = (ULONG)Y * ImageRowBytes;
        const UBYTE* PlaneRows[8];
        UWORD CurrentRGB = BasePal[0];
        UWORD TexOffset = (UWORD)((ULONG)Y * (ULONG)TEXTURE_PACKED_ROW_BYTES);

        for (UWORD Plane = 0; Plane < 8; ++Plane)
        {
            if (Plane < Depth)
            {
                PlaneRows[Plane] = (const UBYTE*)Image->Image.Planes[Plane] + PlaneRowOffset;
            }
            else
            {
                PlaneRows[Plane] = ZeroPlaneRow;
            }
        }

        for (UWORD ByteX = 0; ByteX < ByteColumns; ++ByteX)
        {
            UBYTE P0 = PlaneRows[0][ByteX];
            UBYTE P1 = PlaneRows[1][ByteX];
            UBYTE P2 = PlaneRows[2][ByteX];
            UBYTE P3 = PlaneRows[3][ByteX];
            UBYTE P4 = PlaneRows[4][ByteX];
            UBYTE P5 = PlaneRows[5][ByteX];
            UBYTE P6 = PlaneRows[6][ByteX];
            UBYTE P7 = PlaneRows[7][ByteX];

            for (UWORD Bit = 0; Bit < 8; ++Bit)
            {
                const UBYTE Pixel =
                    (UBYTE)(((P0 >> 7) & 0x01U) |
                            ((P1 >> 6) & 0x02U) |
                            ((P2 >> 5) & 0x04U) |
                            ((P3 >> 4) & 0x08U) |
                            ((P4 >> 3) & 0x10U) |
                            ((P5 >> 2) & 0x20U) |
                            ((P6 >> 1) & 0x40U) |
                            (P7 & 0x80U));
                const UBYTE Data = (UBYTE)(Pixel & 0x0F);
                const UBYTE Ctrl = (UBYTE)(Pixel >> 4);
                UWORD OutRGB;
                ULONG PackedHi;

                P0 <<= 1;
                P1 <<= 1;
                P2 <<= 1;
                P3 <<= 1;
                P4 <<= 1;
                P5 <<= 1;
                P6 <<= 1;
                P7 <<= 1;

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
                PackedHi = PackHamContributionHi(OutRGB);
                *(ULONG*)(TexturePackedHi + TexOffset) = PackedHi;
                *(ULONG*)(TexturePackedLo + TexOffset) = (PackedHi >> 4);
                TexOffset = (UWORD)(TexOffset + TEXTURE_PACKED_STRIDE);
            }
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

static void InitRotoBuffers(void)
{
    // Store each rendered plane as one contiguous 24x48 block. That keeps the
    // visible image identical, but the renderer no longer has to skip over the
    // other three planes at the end of every row. The Copper now advances to
    // the next source row with modulo 0 after each 4-line stretch.
    for (UWORD i = 0; i < 2; ++i)
    {
        RotoBuffers[i] = (UBYTE*)AllocMem(ROTO_VISIBLE_BYTES, MEMF_CHIP | MEMF_CLEAR);
    }
}

// ---------------------------------------------------------------------
// Copper
// ---------------------------------------------------------------------

static UWORD* CopperList = NULL;
static ULONG CopperListSize = 0;

static UWORD BPLPTH_Idx[NUMBEROFBITPLANES];
static UWORD BPLPTL_Idx[NUMBEROFBITPLANES];

static void CopperAppendWait(UWORD* Index, UWORD VPos, UBYTE* Wrapped)
{
    if ((VPos > 0x00FF) && !(*Wrapped))
    {
        CopperList[(*Index)++] = 0xFFDF;
        CopperList[(*Index)++] = 0xFFFE;
        *Wrapped = 1;
    }

    CopperList[(*Index)++] = (UWORD)(((VPos & 0xFF) << 8) | 0x0001);
    CopperList[(*Index)++] = 0xFFFE;
}

static void Init_CopperList(void)
{
    const ULONG CopperWords = 26 + (4 * NUMBEROFBITPLANES) + (SCREEN_COLORS * 2) + (ROTO_MOD_SWITCH_COUNT * 6) + 2;

    CopperListSize = CopperWords * sizeof(UWORD);
    CopperList = (UWORD*)AllocMem(CopperListSize, MEMF_CHIP | MEMF_CLEAR);

    UWORD Index = 0;
    UBYTE WrapWaitInserted = 0;

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

    CopperList[Index++] = 0x0108;
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
        CopperAppendWait(&Index, (UWORD)(ROTO_VPOS_START + Line), &WrapWaitInserted);
        CopperList[Index++] = 0x0108;
        CopperList[Index++] = ROTO_ADVANCE_MOD;
        CopperList[Index++] = 0x010A;
        CopperList[Index++] = ROTO_ADVANCE_MOD;

        CopperAppendWait(&Index, (UWORD)(ROTO_VPOS_START + Line + 1), &WrapWaitInserted);
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
    ULONG Ptr = (ULONG)RotoBuffers[Buffer];
    CopperList[BPLPTH_Idx[0]] = (UWORD)(Ptr >> 16);
    CopperList[BPLPTL_Idx[0]] = (UWORD)(Ptr & 0xFFFF);

    Ptr += ROTO_PLANE_BYTES;
    CopperList[BPLPTH_Idx[1]] = (UWORD)(Ptr >> 16);
    CopperList[BPLPTL_Idx[1]] = (UWORD)(Ptr & 0xFFFF);

    Ptr += ROTO_PLANE_BYTES;
    CopperList[BPLPTH_Idx[2]] = (UWORD)(Ptr >> 16);
    CopperList[BPLPTL_Idx[2]] = (UWORD)(Ptr & 0xFFFF);

    Ptr += ROTO_PLANE_BYTES;
    CopperList[BPLPTH_Idx[3]] = (UWORD)(Ptr >> 16);
    CopperList[BPLPTL_Idx[3]] = (UWORD)(Ptr & 0xFFFF);
}

// ---------------------------------------------------------------------
// Cleanup / main
// ---------------------------------------------------------------------

static void Cleanup_All(void)
{
    FreeMem(CopperList, CopperListSize);
    CopperList = NULL;
    CopperListSize = 0;

    FreeMem(TexturePackedBlock, TexturePackedSize);
    TexturePackedBlock = NULL;

    TexturePackedHi = NULL;
    TexturePackedLo = NULL;
    TexturePackedMidHi = NULL;
    TexturePackedMidLo = NULL;
    TexturePackedSize = 0;

    FreeMem(FrameBlocks, FrameBlocksSize);
    FrameBlocks = NULL;
    FrameBlocksSize = 0;
    CurrentFrameBlock = NULL;
    FrameBlocksEnd = NULL;

    for (UWORD i = 0; i < 2; ++i)
    {
        FreeMem(RotoBuffers[i], ROTO_VISIBLE_BYTES);
        RotoBuffers[i] = NULL;
    }

    lwmf_CleanupAll();
}

int main(void)
{
    lwmf_LoadGraphicsLib();

    InitTexture();
    BuildFrameStates();
    FrameBlocksEnd = FrameBlocks + 256;
    CurrentFrameBlock = &FrameBlocks[1];
    InitRotoBuffers();
    Init_CopperList();

    Update_BitplanePointers(0);
    lwmf_TakeOverOS();

    UBYTE DrawBuffer = 1;

    while (*CIAA_PRA & 0x40)
    {
        RenderFrameAsm(RotoBuffers[DrawBuffer], CurrentFrameBlock);
        ++CurrentFrameBlock;
        if (CurrentFrameBlock == FrameBlocksEnd)
        {
            CurrentFrameBlock = FrameBlocks;
        }

        DBG_COLOR(0x00F);
        lwmf_WaitVertBlank();
        DBG_COLOR(0x000);

        Update_BitplanePointers(DrawBuffer);

        DrawBuffer ^= 1;
    }

    Cleanup_All();
    return 0;
}
