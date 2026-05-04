//**********************************************************************
//* 4x4 HAM7 Rotozoomer                                                *
//*                                                                    *
//* 4 DMA bitplanes, HAM control via BPL5DAT/BPL6DAT, 56 columns       *
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
extern void RenderFastB0P8Entry(void);
extern void RenderFastBm1P8Entry(void);
extern void RenderFastB0U0P8Entry(void);
extern void RenderFastBm1U0P8Entry(void);
extern void RenderFastBp1P8Entry(void);
extern void RenderFastBm2P8Entry(void);
extern void RenderFastBp1U0P8Entry(void);
extern void RenderFastBm2U0P8Entry(void);
extern void RenderFastB0V0Entry(void);
extern void RenderFastB0U0V0Entry(void);

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
#define ROTO_COLUMNS            56
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
#define ROTO_FRAME_COUNT        128
#define ROTO_ANGLE_PHASE_STEP   2
#define ROTO_DELTA_SCALE        3072
#define ROTO_CENTER_U           0x4000
#define ROTO_CENTER_V           0x4000

// ---------------------------------------------------------------------
// Precomputed frame + row state tables
// ---------------------------------------------------------------------

typedef struct
{
    // First four premerged logical texel-pairs, stored plane-wise.
    // Each long is copied directly to one destination plane.
    ULONG PrefixPlaneLongs[4];
    // Pairs 05-08 packed as one long per plane: [p05][p06][p07][p08].
    ULONG PrefixPair05_08Longs[4];
    // Pairs 09-12 packed as one long per plane: [p09][p10][p11][p12].
    ULONG PrefixPair09_12Longs[4];
    // Pairs 13-16 packed as one long per plane: [p13][p14][p15][p16].
    ULONG PrefixPair13_16Longs[4];
    UBYTE PrefixPair17Bytes[4];    // pair 17: one byte per plane
} RotoRowState;

typedef struct RotoFrameBlock
{
    WORD         DuC;
    UBYTE        DuL;
    UBYTE        DvRem;
    void       (*Entry)(void);
    // Initial rolling runtime seed for row 0 after the frame-specific prefix.
    // B0 frames start after pair 07; BM1/BP1/BM2 frames start after pair 08.
    UWORD        InitialPackedSeed;
    // High byte: V fraction. Low byte: U fraction.
    UWORD        InitialPackedBytes;
    // Compact delta applied before rendering each row after the first one.
    WORD         PostRowDuC;
    UBYTE        PostRowDuL;
    UBYTE        DvRemPad;  // padding to keep PostRowVBase word-aligned
    WORD         PostRowVBase;
    UWORD        PostRowVRemShift;
    // Next frame address (all frames have uniform 68-byte row size).
    struct RotoFrameBlock* NextFrame;
    RotoRowState Rows[ROTO_ROWS];
} RotoFrameBlock;

typedef char RotoRowStateSizeMustBe68[(sizeof(RotoRowState) == 68) ? 1 : -1];
typedef char RotoFrameBlockHeaderAndBaseRowsMustBe3288[(sizeof(RotoFrameBlock) == 3288) ? 1 : -1];

#define ROTO_FRAME_HEADER_BYTES 24UL
#define ROTO_ROW_BYTES          68UL  // uniform P17 row: 16+16+16+16+4 bytes
#define ROTO_PREFIX_PAIRS       17UL  // all frames precompute pairs 01-17

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
// RotoBuffers: Chip-RAM display buffers used by Bitplane DMA.
// Double-buffered: CPU renders into RotoBuffers[DrawBuffer] while the
// Copper displays RotoBuffers[DrawBuffer^1].  No intermediate copy needed.
static UBYTE* RotoBuffers[2]  = { NULL, NULL };

// CurrentFrameBlock is seeded after BuildFrameStates() so the
// first rendered image still matches the former phase-updated-before-render
// sequence. BuildFrameStates folds pair 07 into every row state and places
// pair 08 directly after that row state for every non-B0 vertical family and B0 DvDx>=112 frames.
// InitTexture() must have run first.

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

#define Asr6Word(v) ((WORD)((LONG)(v) >> 6))
#define Asr1Word(v) ((WORD)((LONG)(v) >> 1))
#define Asr8Word(v) ((WORD)((LONG)(v) >> 8))
#define Low6Quad(v) ((WORD)((((UWORD)(v)) & 0x003Fu) << 2))

static void BuildFrameStates(void)
{
    // The shipped effect only ever walks one fixed ROTO_FRAME_COUNT-frame cycle. Build the
    // exact prefix bytes for each frame and each rendered row once so the
    // assembler can skip most row setup: all 13 prefix pairs are precomputed,
    // leaving only 9 runtime pairs (14-22) per row.
    UBYTE* FrameWrite;
    RotoFrameBlock* PreviousState = NULL;

    // All frames use the same uniform 52-byte row layout (P13).
    FrameBlocksSize = (ULONG)ROTO_FRAME_COUNT * (ROTO_FRAME_HEADER_BYTES + (ULONG)ROTO_ROWS * ROTO_ROW_BYTES);

    FrameBlocks = (RotoFrameBlock*)lwmf_AllocCpuMem(FrameBlocksSize, MEMF_CLEAR);
    FrameWrite = (UBYTE*)FrameBlocks;

    for (UWORD Frame = 0; Frame < ROTO_FRAME_COUNT; ++Frame)
    {
        const UBYTE AnglePhase = (UBYTE)(Frame * ROTO_ANGLE_PHASE_STEP);
        const UBYTE ZoomPhase = (UBYTE)(Frame * 2);
        const UBYTE MovePhaseX = (UBYTE)(Frame * 2);
        const UBYTE MovePhaseY = (UBYTE)(64 + (Frame * 2));
        const LONG ZoomIndex = (LONG)(((ULONG)SinTab256[ZoomPhase] * 31UL) / 63UL);
        const LONG Zoom = (LONG)ROTO_ZOOM_BASE - (LONG)ROTO_ZOOM_AMPLITUDE + ((ZoomIndex * ((LONG)ROTO_ZOOM_AMPLITUDE * 2L)) / (LONG)(ROTO_ZOOM_STEPS - 1));
        const LONG SinV = (LONG)((WORD)SinTab256[AnglePhase] - 32);
        const LONG CosV = (LONG)((WORD)SinTab256[(UBYTE)(AnglePhase + 64)] - 32);
        const WORD DuDx = (WORD)((CosV * ROTO_DELTA_SCALE) / Zoom);
        const WORD DvDx = (WORD)((SinV * ROTO_DELTA_SCALE) / Zoom);
        const WORD StartUOffset = (WORD)(-((LONG)ROTO_HALF_COLUMNS * (LONG)DuDx) + ((LONG)ROTO_HALF_ROWS * (LONG)DvDx));
        const WORD StartVOffset = (WORD)(-((LONG)ROTO_HALF_COLUMNS * (LONG)DvDx) - ((LONG)ROTO_HALF_ROWS * (LONG)DuDx));
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
        const WORD StartVTrans = (WORD)((WORD)((((ULONG)BaseV) << 1) ^ 0x8000UL) + StartVTransOffset);
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
        ULONG UPostRowAdvance;
        UWORD VSampleStep = 0;
        UWORD WRowAdvance;
        UWORD WPostRowAdvance;
        UWORD Family = ROTO_FAMILY_B0;
        RotoFrameBlock* State;
        UBYTE* RowWrite;

        // All frames use the uniform P13 row layout (52 bytes, pairs 01-13 precomputed).
        const ULONG RowStride = ROTO_ROW_BYTES;
        const UWORD PrefixPairs = (UWORD)ROTO_PREFIX_PAIRS;

        if (DvDx < 0)
        {
            Family = (DvDx < -256) ? ROTO_FAMILY_BM2 : ROTO_FAMILY_BM1;
        }
        else if (DvDx > 255)
        {
            Family = ROTO_FAMILY_BP1;
        }

        State = (RotoFrameBlock*)FrameWrite;
        RowWrite = FrameWrite + ROTO_FRAME_HEADER_BYTES;
        FrameWrite += ROTO_FRAME_HEADER_BYTES + ((ULONG)ROTO_ROWS * RowStride);

        if (PreviousState)
        {
            PreviousState->NextFrame = State;
        }

        PreviousState = State;

        State->NextFrame = (RotoFrameBlock*)FrameWrite;

        State->DuC = DuC;
        State->DuL = DuLByte;
        State->DvRem = DvRem;

        // All frames use the P13 row layout. V0 frames still use dedicated
        // entry points that skip the V-carry checks in the 9 runtime pairs.
        if (Family == ROTO_FAMILY_B0)
        {
            if (DvRem == 0)
            {
                State->Entry = (DuLByte == 0) ? RenderFastB0U0V0Entry : RenderFastB0V0Entry;
            }
            else
            {
                State->Entry = (DuLByte == 0) ? RenderFastB0U0P8Entry : RenderFastB0P8Entry;
            }

            VSampleStep = (UWORD)DvRem;
        }
        else if (Family == ROTO_FAMILY_BM1)
        {
            State->Entry = (DuLByte == 0) ? RenderFastBm1U0P8Entry : RenderFastBm1P8Entry;
            VSampleStep = (UWORD)(0xFF00U | (UWORD)DvRem);
        }
        else if (Family == ROTO_FAMILY_BM2)
        {
            State->Entry = (DuLByte == 0) ? RenderFastBm2U0P8Entry : RenderFastBm2P8Entry;
            VSampleStep = (UWORD)(0xFE00U | (UWORD)DvRem);
        }
        else
        {
            State->Entry = (DuLByte == 0) ? RenderFastBp1U0P8Entry : RenderFastBp1P8Entry;
            VSampleStep = (UWORD)(0x0100U | (UWORD)DvRem);
        }

        URowAdvance = (((ULONG)ROTO_COLUMNS * ((((ULONG)DuCWord) << 8) | (ULONG)DuLByte)) + ((((ULONG)RowStepUcWord) << 8) | (ULONG)RowStepUlByte)) & 0x00FFFFFFUL;
        WRowAdvance = (UWORD)(((ULONG)ROTO_COLUMNS * (ULONG)VSampleStep + (ULONG)RowStepVWord) & 0xFFFFUL);

        // Runtime intentionally skips the accumulator update after the final
        // rendered sample of the row. Fold that one skipped sample advance into
        // the post-row delta together with the next row's folded prefix samples.
        UPostRowAdvance = ((((ULONG)((PrefixPairs * 2U) + 1U) * ((((ULONG)DuCWord) << 8) | (ULONG)DuLByte)) + ((((ULONG)RowStepUcWord) << 8) | (ULONG)RowStepUlByte)) & 0x00FFFFFFUL);
        WPostRowAdvance = (UWORD)((((ULONG)((PrefixPairs * 2U) + 1U) * (ULONG)VSampleStep) + (ULONG)RowStepVWord) & 0xFFFFUL);

        State->PostRowDuC = (WORD)(UPostRowAdvance >> 8);
        State->PostRowDuL = (UBYTE)UPostRowAdvance;
        State->DvRemPad   = 0;
        State->PostRowVBase = (WORD)((LONG)Asr8Word((WORD)WPostRowAdvance) * 0x0200L);
        State->PostRowVRemShift = (UWORD)(((UWORD)(UBYTE)WPostRowAdvance) << 8);

        for (UWORD Row = 0; Row < ROTO_ROWS; ++Row)
        {
            RotoRowState* RowSeed = (RotoRowState*)RowWrite;
            ULONG PrefixUState = UState;
            UWORD PrefixWState = WState;
            // Groups 0-3 accumulate pairs 01-04, 05-08, 09-12, 13-16 as longs per plane.
            ULONG PrefixGroupLongs[4][4] = {{ 0 }};

            for (UWORD Pair = 0; Pair < 17; ++Pair)
            {
                const UWORD StartOffset0 = (UWORD)(((PrefixWState << 1) & 0xFE00U) + ((UWORD)(PrefixUState >> 8) & 0x01FCU));

                PrefixUState = (PrefixUState + USampleAdvance) & 0x00FFFFFFUL;
                PrefixWState = (UWORD)((PrefixWState + VSampleStep) & 0xFFFFU);

                const UWORD StartOffset1 = (UWORD)(((PrefixWState << 1) & 0xFE00U) + ((UWORD)(PrefixUState >> 8) & 0x01FCU));

                const ULONG Packed = (*(const ULONG*)((const UBYTE*)TexturePackedMidHi + (WORD)StartOffset0)) | (*(const ULONG*)((const UBYTE*)TexturePackedMidLo + (WORD)StartOffset1));

                if (Pair < 16)
                {
                    const UWORD Group = Pair >> 2;
                    PrefixGroupLongs[Group][0] = (PrefixGroupLongs[Group][0] << 8) | (ULONG)(UBYTE)(Packed);
                    PrefixGroupLongs[Group][1] = (PrefixGroupLongs[Group][1] << 8) | (ULONG)(UBYTE)(Packed >> 8);
                    PrefixGroupLongs[Group][2] = (PrefixGroupLongs[Group][2] << 8) | (ULONG)(UBYTE)(Packed >> 16);
                    PrefixGroupLongs[Group][3] = (PrefixGroupLongs[Group][3] << 8) | (ULONG)(UBYTE)(Packed >> 24);
                }
                else
                {
                    RowSeed->PrefixPair17Bytes[0] = (UBYTE)Packed;
                    RowSeed->PrefixPair17Bytes[1] = (UBYTE)(Packed >> 8);
                    RowSeed->PrefixPair17Bytes[2] = (UBYTE)(Packed >> 16);
                    RowSeed->PrefixPair17Bytes[3] = (UBYTE)(Packed >> 24);
                }

                PrefixUState = (PrefixUState + USampleAdvance) & 0x00FFFFFFUL;
                PrefixWState = (UWORD)((PrefixWState + VSampleStep) & 0xFFFFU);
            }

            if (Row == 0)
            {
                const UWORD NextUc = (UWORD)(((UWORD)(PrefixUState >> 8)) & 0x01FFU);
                const UWORD NextRow = (UWORD)((PrefixWState << 1) & 0xFE00U);

                State->InitialPackedSeed = (UWORD)(NextRow | NextUc);
                State->InitialPackedBytes = (UWORD)((((UWORD)PrefixWState & 0x00FFU) << 8) | (UWORD)(PrefixUState & 0x00FFUL));
            }

            for (UWORD Pl = 0; Pl < 4U; ++Pl)
            {
                RowSeed->PrefixPlaneLongs[Pl]     = PrefixGroupLongs[0][Pl];
                RowSeed->PrefixPair05_08Longs[Pl] = PrefixGroupLongs[1][Pl];
                RowSeed->PrefixPair09_12Longs[Pl] = PrefixGroupLongs[2][Pl];
                RowSeed->PrefixPair13_16Longs[Pl] = PrefixGroupLongs[3][Pl];
            }

            RowWrite += RowStride;

            UState = (UState + URowAdvance) & 0x00FFFFFFUL;
            WState = (UWORD)((WState + WRowAdvance) & 0xFFFFU);
        }
    }

    if (PreviousState)
    {
        PreviousState->NextFrame = FrameBlocks;
    }
}

#define PackHamContributionHi(Color) \
    (HamPackedR[((Color) >> 8) & 0x0F] | \
     HamPackedG[((Color) >> 4) & 0x0F] | \
     HamPackedB[(Color) & 0x0F])

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

enum
{
    COPPER_BPL0PTH_IDX = 23,
    COPPER_BPL0PTL_IDX = 25,
    COPPER_BPL1PTH_IDX = 27,
    COPPER_BPL1PTL_IDX = 29,
    COPPER_BPL2PTH_IDX = 31,
    COPPER_BPL2PTL_IDX = 33,
    COPPER_BPL3PTH_IDX = 35,
    COPPER_BPL3PTL_IDX = 37
};

static UWORD RotoBufferCopperWords[2][NUMBEROFBITPLANES * 2];

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

    // Display window and data-fetch setup. The visible area is centered in
    // a normal PAL lowres screen, while DDF fetches only the 176 roto pixels.
    CopperList[Index++] = 0x008E;
    CopperList[Index++] = ROTO_DIWSTRT;
    CopperList[Index++] = 0x0090;
    CopperList[Index++] = ROTO_DIWSTOP;
    CopperList[Index++] = 0x0092;
    CopperList[Index++] = ROTO_DDFSTRT;
    CopperList[Index++] = 0x0094;
    CopperList[Index++] = ROTO_DDFSTOP;

    // Bitplane control setup. The display runs in HAM mode with the requested
    // plane count; BPLCON1/BPLCON2 stay neutral because no scrolling or
    // playfield-priority tricks are used.
    CopperList[Index++] = 0x0100;
    CopperList[Index++] = (UWORD)((HAM_DISPLAY_BPU << 12) | 0x0A00);
    CopperList[Index++] = 0x0102;
    CopperList[Index++] = 0x0000;
    CopperList[Index++] = 0x0104;
    CopperList[Index++] = 0x0000;

    // Start in row-repeat mode. The copper switches to modulo zero for one
    // scanline out of every four so each rendered row is stretched to 4x4.
    CopperList[Index++] = 0x0108;
    CopperList[Index++] = ROTO_REPEAT_MOD;
    CopperList[Index++] = 0x010A;
    CopperList[Index++] = ROTO_REPEAT_MOD;

    // Constant HAM control-plane data. These registers provide stable control
    // bits for the whole line while the CPU renderer writes the data planes.
    CopperList[Index++] = 0x0118;
    CopperList[Index++] = HAM_CONTROL_WORD_P5;
    CopperList[Index++] = 0x011A;
    CopperList[Index++] = HAM_CONTROL_WORD_P6;

    // Bitplane pointer placeholders. Their data-word positions are fixed by
    // the layout above so the main loop can patch them with constant indexes.
    for (UWORD Plane = 0; Plane < NUMBEROFBITPLANES; ++Plane)
    {
        CopperList[Index++] = (UWORD)(0x00E0 + (Plane * 4));
        CopperList[Index++] = 0x0000;

        CopperList[Index++] = (UWORD)(0x00E2 + (Plane * 4));
        CopperList[Index++] = 0x0000;
    }

    // Palette upload. Only the base palette is loaded here; HAM changes the
    // running RGB value per pixel through the encoded image data.
    for (UWORD c = 0; c < SCREEN_COLORS; ++c)
    {
        CopperList[Index++] = (UWORD)(0x0180 + (c * 2));
        CopperList[Index++] = DisplayPalette[c];
    }

    // 4x vertical stretch. For each rendered source row, the first three
    // scanlines repeat the same bitplane addresses; the fourth scanline uses
    // modulo zero so DMA advances to the next source row.
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

    // End marker and activation of the generated copper list.
    CopperList[Index++] = 0xFFFF;
    CopperList[Index++] = 0xFFFE;

    *COP1LC = (ULONG)CopperList;
}

static void BuildRotoBufferCopperWords(void)
{
    for (UWORD Buffer = 0; Buffer < 2; ++Buffer)
    {
        ULONG Ptr = (ULONG)RotoBuffers[Buffer];
        UWORD* Words = RotoBufferCopperWords[Buffer];

        for (UWORD Plane = 0; Plane < NUMBEROFBITPLANES; ++Plane)
        {
            Words[(Plane * 2) + 0] = (UWORD)(Ptr >> 16);
            Words[(Plane * 2) + 1] = (UWORD)Ptr;
            Ptr += ROTO_PLANE_BYTES;
        }
    }
}

inline static void Update_BitplanePointers(UBYTE Buffer)
{
    const UWORD* Words = RotoBufferCopperWords[Buffer];

    CopperList[COPPER_BPL0PTH_IDX] = Words[0];
    CopperList[COPPER_BPL0PTL_IDX] = Words[1];
    CopperList[COPPER_BPL1PTH_IDX] = Words[2];
    CopperList[COPPER_BPL1PTL_IDX] = Words[3];
    CopperList[COPPER_BPL2PTH_IDX] = Words[4];
    CopperList[COPPER_BPL2PTL_IDX] = Words[5];
    CopperList[COPPER_BPL3PTH_IDX] = Words[6];
    CopperList[COPPER_BPL3PTL_IDX] = Words[7];
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
    CurrentFrameBlock = FrameBlocks->NextFrame;
    InitRotoBuffers();
    BuildRotoBufferCopperWords();
    Init_CopperList();

    Update_BitplanePointers(0);
    lwmf_TakeOverOS();

    UBYTE DrawBuffer = 1;

    while (*CIAA_PRA & 0x40)
    {
        RenderFrameAsm(RotoBuffers[DrawBuffer], CurrentFrameBlock);
        CurrentFrameBlock = CurrentFrameBlock->NextFrame;

        DBG_COLOR(0x00F);
        lwmf_WaitVertBlank();
        DBG_COLOR(0x000);

        Update_BitplanePointers(DrawBuffer);

        DrawBuffer ^= 1;
    }

    Cleanup_All();
    return 0;
}
