//**********************************************************************
//* 4x4 HAM7 BPLDAT Quirk Rotozoomer                                   *
//*                                                                    *
//* 4 DMA bitplanes carry HAM data nibbles. BPL5DAT/BPL6DAT provide    *
//* fixed HAM control-bit patterns for a direct/red/green/blue cell.   *
//* Amiga 500 OCS, 512kb Chip + 512kb Slowmem                          *
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
#include "Rotozoomer_shared.h"

// ---------------------------------------------------------------------
// Debugging
// ---------------------------------------------------------------------

#define DEBUG 0

#if DEBUG
#define DBG_COLOR(c) (*COLOR00 = (c))
#else
#define DBG_COLOR(c)
#endif

// ---------------------------------------------------------------------
// Effect constants
// ---------------------------------------------------------------------

#define TEXTURE_FILENAME        "gfx/128x128_ham.iff"
#define TEXTURE_SOURCE_WIDTH    128
#define TEXTURE_SOURCE_HEIGHT   128
#define TEXTURE_WIDTH           128
#define TEXTURE_HEIGHT          128
#define TEXTURE_EXPANDED_HEIGHT 256
#define TEXTURE_SOURCE_PLANES   6

#define TEXTURE_CELL_BYTES      ((ULONG)TEXTURE_WIDTH * TEXTURE_EXPANDED_HEIGHT * sizeof(UWORD))
#define PAIR_TABLE_BYTES        (4096 * 8)

#define WORD_HI(v)              ((UWORD)((ULONG)(v) >> 16))
#define WORD_LO(v)              ((UWORD)((ULONG)(v) & 0xFFFF))
#define BPLPTH(p)               (0x00E0 + ((p) << 2))
#define BPLPTL(p)               (0x00E2 + ((p) << 2))
#define PHASE8(v)               ((UBYTE)(v))

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
    9,9,8,8,7,7,6,6,5,5,4,4,4,3,3,3,2,2,2,2,1,1,1,1,1,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,1,1,1,1,1,2,2,2,2,3,3,3,4,4,4,5,5,6,6,7,7,8,8,9,
    9,10,10,11,12,12,13,13,14,15,15,16,17,17,18,19,19,20,21,22,22,23,24,25,25,26,27,28,28,29,30,31
};

// ---------------------------------------------------------------------
// Texture and display state
// ---------------------------------------------------------------------

static UBYTE* SlowBlock = NULL;
static UWORD* TextureCells = NULL;
static UBYTE* PairTables = NULL;
static UBYTE* HalfRowCache = NULL;
static UBYTE* SlowRowCache = NULL;
static UBYTE* HamBuffers[2] = { NULL, NULL };
static UWORD* CopperLists[2] = { NULL, NULL };
static UBYTE* ChipBlock = NULL;
static UWORD BasePalette[16];

struct HamFrameParams
{
    WORD  DuDx;
    WORD  DvDx;
    WORD  RowUDelta;
    WORD  RowVDelta;
    UWORD RowU;
    UWORD RowV;
    UWORD TemporalUpperU;
    UWORD TemporalUpperV;
    UWORD TemporalLowerU;
    UWORD TemporalLowerV;
    UWORD HalfRowU;
    UWORD HalfRowV;
    UWORD SlowRowU;
    UWORD SlowRowV;
};

static struct HamFrameParams* FrameParams = NULL;
static UWORD* HalfPointerWords = NULL;
static UBYTE* UOffsetTable = NULL;
static UBYTE* UOffsetTableMid = NULL;
#define FRAME_PARAMS_BYTES      (HAM_FRAME_COUNT * sizeof(struct HamFrameParams))
#define UOFFSET_TABLE_BYTES     65536
#define SLOW_BLOCK_BYTES        (TEXTURE_CELL_BYTES + PAIR_TABLE_BYTES + FRAME_PARAMS_BYTES + HAM_HALFRATE_POINTER_BYTES + UOFFSET_TABLE_BYTES)

void RenderHamLiveRowsAsm(__reg("a0") UBYTE* Buffer,
                          __reg("a1") const UWORD* TextureCellsMid,
                          __reg("a2") const UBYTE* UOffsetTableMid,
                          __reg("a3") const UBYTE* PairTables,
                          __reg("d0") UWORD RowU,
                          __reg("d1") UWORD RowV,
                          __reg("d2") WORD DuDx,
                          __reg("d3") WORD DvDx,
                          __reg("d6") WORD RowUDelta,
                          __reg("d7") WORD RowVDelta);

void RenderHamTemporalUpperRowsAsm(__reg("a0") UBYTE* Buffer,
                                   __reg("a1") const UWORD* TextureCellsMid,
                                   __reg("a2") const UBYTE* UOffsetTableMid,
                                   __reg("a3") const UBYTE* PairTables,
                                   __reg("d0") UWORD RowU,
                                   __reg("d1") UWORD RowV,
                                   __reg("d2") WORD DuDx,
                                   __reg("d3") WORD DvDx,
                                   __reg("d6") WORD RowUDelta,
                                   __reg("d7") WORD RowVDelta);

void RenderHamTemporalLowerRowsAsm(__reg("a0") UBYTE* Buffer,
                                   __reg("a1") const UWORD* TextureCellsMid,
                                   __reg("a2") const UBYTE* UOffsetTableMid,
                                   __reg("a3") const UBYTE* PairTables,
                                   __reg("d0") UWORD RowU,
                                   __reg("d1") UWORD RowV,
                                   __reg("d2") WORD DuDx,
                                   __reg("d3") WORD DvDx,
                                   __reg("d6") WORD RowUDelta,
                                   __reg("d7") WORD RowVDelta);

void CopyHamTemporalUpperRowsAsm(__reg("a0") UBYTE* Target,
                                 __reg("a1") const UBYTE* Source);

void CopyHamTemporalLowerRowsAsm(__reg("a0") UBYTE* Target,
                                 __reg("a1") const UBYTE* Source);

void InitHamBlitterCopyModeAsm(void);

void RenderHamHalfRowsAsm(__reg("a0") UBYTE* Buffer,
                          __reg("a1") const UWORD* TextureCellsMid,
                          __reg("a2") const UBYTE* UOffsetTableMid,
                          __reg("a3") const UBYTE* PairTables,
                          __reg("d0") UWORD RowU,
                          __reg("d1") UWORD RowV,
                          __reg("d2") WORD DuDx,
                          __reg("d3") WORD DvDx,
                          __reg("d6") WORD RowUDelta,
                          __reg("d7") WORD RowVDelta);

void RenderHamSlowRowsAsm(__reg("a0") UBYTE* Buffer,
                          __reg("a1") const UWORD* TextureCellsMid,
                          __reg("a2") const UBYTE* UOffsetTableMid,
                          __reg("a3") const UBYTE* PairTables,
                          __reg("d0") UWORD RowU,
                          __reg("d1") UWORD RowV,
                          __reg("d2") WORD DuDx,
                          __reg("d3") WORD DvDx,
                          __reg("d6") WORD RowUDelta,
                          __reg("d7") WORD RowVDelta);

void UpdateHamCachedPointersAsm(__reg("a0") UWORD* List,
                                 __reg("a1") const UWORD* HalfPointers,
                                 __reg("a2") const UBYTE* SlowRows);

void WaitHamLiveDoneAndSwitchCopperAsm(__reg("a0") UWORD* List);

// ---------------------------------------------------------------------
// Texture conversion
// ---------------------------------------------------------------------

static void BuildTextureRGB4FromHAM(const struct lwmf_Image* Image)
{
    const UWORD ByteColumns = TEXTURE_SOURCE_WIDTH >> 3;
    const ULONG ImageRowBytes = Image->Image.BytesPerRow;

    for (UWORD i = 0; i < 16; ++i)
    {
        BasePalette[i] = (UWORD)(Image->CRegs[i] & 0x0FFF);
    }

    for (UWORD Y = 0; Y < TEXTURE_SOURCE_HEIGHT; ++Y)
    {
        const ULONG PlaneRowOffset = (ULONG)Y * ImageRowBytes;
        const UBYTE* PlaneRows[TEXTURE_SOURCE_PLANES];
        UWORD CurrentRGB = BasePalette[0];
        UWORD* Out = TextureCells + ((ULONG)Y * TEXTURE_WIDTH);
        UWORD* OutMirror = TextureCells + (((ULONG)Y + TEXTURE_HEIGHT) * TEXTURE_WIDTH);

        for (UWORD Plane = 0; Plane < TEXTURE_SOURCE_PLANES; ++Plane)
        {
            PlaneRows[Plane] = (const UBYTE*)Image->Image.Planes[Plane] + PlaneRowOffset;
        }

        for (UWORD ByteX = 0; ByteX < ByteColumns; ++ByteX)
        {
            UBYTE P0 = PlaneRows[0][ByteX];
            UBYTE P1 = PlaneRows[1][ByteX];
            UBYTE P2 = PlaneRows[2][ByteX];
            UBYTE P3 = PlaneRows[3][ByteX];
            UBYTE P4 = PlaneRows[4][ByteX];
            UBYTE P5 = PlaneRows[5][ByteX];

            for (UWORD Bit = 0; Bit < 8; ++Bit)
            {
                const UBYTE Pixel =
                    ((P0 >> 7) & 0x01) |
                    ((P1 >> 6) & 0x02) |
                    ((P2 >> 5) & 0x04) |
                    ((P3 >> 4) & 0x08) |
                    ((P4 >> 3) & 0x10) |
                    ((P5 >> 2) & 0x20);
                const UBYTE Data = Pixel & 0x0F;
                const UBYTE Ctrl = Pixel >> 4;
                UWORD OutRGB;

                P0 <<= 1;
                P1 <<= 1;
                P2 <<= 1;
                P3 <<= 1;
                P4 <<= 1;
                P5 <<= 1;

                switch (Ctrl)
                {
                    case 0:
                        OutRGB = BasePalette[Data];
                        break;

                    case 1:
                        OutRGB = (CurrentRGB & 0x0FF0) | Data;
                        break;

                    case 2:
                        OutRGB = (CurrentRGB & 0x00FF) | ((UWORD)Data << 8);
                        break;

                    default:
                        OutRGB = (CurrentRGB & 0x0F0F) | ((UWORD)Data << 4);
                        break;
                }

                CurrentRGB = OutRGB;
                const UWORD Index = (UWORD)(OutRGB << 3);

                *Out++ = Index;
                *OutMirror++ = Index;
            }
        }
    }
}

static void BuildPairTables(void)
{
    ULONG* PairTableLongs = (ULONG*)PairTables;

    for (UWORD Color = 0; Color < 4096; ++Color)
    {
        const UBYTE R = (Color >> 8) & 0x0F;
        const UBYTE G = (Color >> 4) & 0x0F;
        const UBYTE B = Color & 0x0F;
        ULONG HighWord = 0;
        ULONG LowWord = 0;

        for (WORD Plane = 3; Plane >= 0; --Plane)
        {
            const UBYTE Nibble = (UBYTE)((((R >> Plane) & 1) << 2) | (((G >> Plane) & 1) << 1) | ((B >> Plane) & 1));

            HighWord = (HighWord << 8) | (UBYTE)(Nibble << 4);
            LowWord = (LowWord << 8) | Nibble;
        }

        *PairTableLongs++ = HighWord;
        *PairTableLongs++ = LowWord;
    }
}

static void BuildUOffsetTable(void)
{
    for (ULONG i = 0; i < UOFFSET_TABLE_BYTES; ++i)
    {
        UOffsetTable[(UWORD)(i + 32768)] = (UBYTE)((i >> 7) & 0xFE);
    }
}

static void BuildFrameParams(void)
{
    for (UWORD Frame = 0; Frame < HAM_FRAME_COUNT; ++Frame)
    {
        const UBYTE AnglePhase = PHASE8(Frame * HAM_ANGLE_PHASE_STEP);
        const WORD SinA = (WORD)SinTab256[AnglePhase] - 32;
        const WORD CosA = (WORD)SinTab256[PHASE8(AnglePhase + 64)] - 32;
        const WORD Zoom = HAM_ZOOM_BASE + ((((WORD)SinTab256[AnglePhase] - 32) * HAM_ZOOM_AMPLITUDE) >> 5);
        const WORD DuDx = (CosA * Zoom) >> 5;
        const WORD DvDx = (SinA * Zoom) >> 5;
        const WORD MoveU = (WORD)SinTab256[PHASE8(Frame)] - 32;
        const WORD MoveV = (WORD)SinTab256[PHASE8(Frame + 64)] - 32;
        const LONG CenterU = HAM_CENTER_U + ((LONG)MoveU << 8);
        const LONG CenterV = HAM_CENTER_V + ((LONG)MoveV << 8);
        const LONG OffsetU = (HAM_HALF_COLUMNS * DuDx) - (HAM_HALF_ROWS * DvDx);
        const LONG OffsetV = (HAM_HALF_COLUMNS * DvDx) + (HAM_HALF_ROWS * DuDx);

        const LONG RowUDelta = -((LONG)(HAM_COLUMNS - 1) * DuDx) - DvDx;
        const LONG RowVDelta = DuDx - ((LONG)(HAM_COLUMNS - 1) * DvDx);
        const UWORD RowU = (UWORD)(CenterU - OffsetU);
        const UWORD RowV = (UWORD)(CenterV - OffsetV);

        FrameParams[Frame].DuDx = DuDx;
        FrameParams[Frame].DvDx = DvDx;
        FrameParams[Frame].RowUDelta = (WORD)RowUDelta;
        FrameParams[Frame].RowVDelta = (WORD)RowVDelta;
        FrameParams[Frame].RowU = RowU;
        FrameParams[Frame].RowV = RowV;
        FrameParams[Frame].TemporalUpperU = (UWORD)(RowU - ((LONG)HAM_TEMPORAL_START_ROW * DvDx));
        FrameParams[Frame].TemporalUpperV = (UWORD)(RowV + ((LONG)HAM_TEMPORAL_START_ROW * DuDx));
        FrameParams[Frame].TemporalLowerU = (UWORD)(RowU - ((LONG)(HAM_TEMPORAL_START_ROW + HAM_TEMPORAL_HALF_ROWS) * DvDx));
        FrameParams[Frame].TemporalLowerV = (UWORD)(RowV + ((LONG)(HAM_TEMPORAL_START_ROW + HAM_TEMPORAL_HALF_ROWS) * DuDx));
        FrameParams[Frame].HalfRowU = (UWORD)(RowU - ((LONG)HAM_HALFRATE_START_ROW * DvDx));
        FrameParams[Frame].HalfRowV = (UWORD)(RowV + ((LONG)HAM_HALFRATE_START_ROW * DuDx));
        FrameParams[Frame].SlowRowU = (UWORD)(RowU - ((LONG)HAM_SLOW_START_ROW * DvDx));
        FrameParams[Frame].SlowRowV = (UWORD)(RowV + ((LONG)HAM_SLOW_START_ROW * DuDx));
    }
}

static void BuildSlowRowCache(void)
{
    UBYTE* Bitmap = SlowRowCache;
    const UWORD* const TextureCellsMid = TextureCells + 16384;
    const UBYTE* const UOffsetMid = UOffsetTableMid;
    const UBYTE* const PairTablesBase = PairTables;

    for (UWORD Frame = 0; Frame < HAM_FRAME_COUNT; ++Frame)
    {
        const struct HamFrameParams* Params = FrameParams + Frame;

        RenderHamSlowRowsAsm(Bitmap, TextureCellsMid, UOffsetMid, PairTablesBase, Params->SlowRowU, Params->SlowRowV, Params->DuDx, Params->DvDx, Params->RowUDelta, Params->RowVDelta);

        Bitmap += HAM_SLOW_ROW_CACHE_FRAME_BYTES;
    }
}

static void BuildHalfRowCache(void)
{
    UBYTE* Bitmap = HalfRowCache;
    UWORD* HalfPointers = HalfPointerWords;
    const UWORD* const TextureCellsMid = TextureCells + 16384;
    const UBYTE* const UOffsetMid = UOffsetTableMid;
    const UBYTE* const PairTablesBase = PairTables;

    for (UWORD Frame = 0; Frame < HAM_FRAME_COUNT; Frame += 2)
    {
        const struct HamFrameParams* Params = FrameParams + Frame;
        ULONG Ptr = (ULONG)Bitmap;

        *HalfPointers++ = WORD_HI(Ptr);
        *HalfPointers++ = WORD_LO(Ptr);
        Ptr += HAM_HALFRATE_ROW_CACHE_PLANE_BYTES;
        *HalfPointers++ = WORD_HI(Ptr);
        *HalfPointers++ = WORD_LO(Ptr);
        Ptr += HAM_HALFRATE_ROW_CACHE_PLANE_BYTES;
        *HalfPointers++ = WORD_HI(Ptr);
        *HalfPointers++ = WORD_LO(Ptr);
        Ptr += HAM_HALFRATE_ROW_CACHE_PLANE_BYTES;
        *HalfPointers++ = WORD_HI(Ptr);
        *HalfPointers++ = WORD_LO(Ptr);

        RenderHamHalfRowsAsm(Bitmap, TextureCellsMid, UOffsetMid, PairTablesBase, Params->HalfRowU, Params->HalfRowV, Params->DuDx, Params->DvDx, Params->RowUDelta, Params->RowVDelta);

        Bitmap += HAM_HALFRATE_ROW_CACHE_FRAME_BYTES;
    }
}

static void InitTexture(void)
{
    struct lwmf_Image* Image = lwmf_LoadImage(TEXTURE_FILENAME);

    SlowBlock = (UBYTE*)lwmf_AllocCpuMem(SLOW_BLOCK_BYTES, 0);
    TextureCells = (UWORD*)SlowBlock;
    PairTables = SlowBlock + TEXTURE_CELL_BYTES;
    FrameParams = (struct HamFrameParams*)(SlowBlock + TEXTURE_CELL_BYTES + PAIR_TABLE_BYTES);
    HalfPointerWords = (UWORD*)(SlowBlock + TEXTURE_CELL_BYTES + PAIR_TABLE_BYTES + FRAME_PARAMS_BYTES);
    UOffsetTable = (UBYTE*)HalfPointerWords + HAM_HALFRATE_POINTER_BYTES;
    UOffsetTableMid = UOffsetTable + 32768;
    SlowRowCache = (UBYTE*)AllocMem(HAM_SLOW_ROW_CACHE_BYTES, MEMF_CHIP);

    BuildTextureRGB4FromHAM(Image);
    lwmf_DeleteImage(Image);

    BuildPairTables();
    BuildUOffsetTable();
    BuildFrameParams();
    BuildSlowRowCache();
}

// ---------------------------------------------------------------------
// Copper
// ---------------------------------------------------------------------

static void CopperAppendWait(UWORD* List, UWORD* Index, UWORD VPos, UBYTE* Wrapped)
{
    if ((VPos > 0x00FF) && !(*Wrapped))
    {
        List[(*Index)++] = 0xFFDF;
        List[(*Index)++] = 0xFFFE;
        *Wrapped = 1;
    }

    List[(*Index)++] = (UWORD)(((VPos & 0xFF) << 8) | 0x0007);
    List[(*Index)++] = 0xFFFE;
}

static void CopperAppendBitplanePointerSlots(UWORD* List, UWORD* Index)
{
    for (UWORD Plane = 0; Plane < 4; ++Plane)
    {
        List[(*Index)++] = BPLPTH(Plane);
        List[(*Index)++] = 0x0000;
        List[(*Index)++] = BPLPTL(Plane);
        List[(*Index)++] = 0x0000;
    }
}

static void CopperAppendModulo(UWORD* List, UWORD* Index, UWORD Modulo)
{
    List[(*Index)++] = 0x0108;
    List[(*Index)++] = Modulo;
    List[(*Index)++] = 0x010A;
    List[(*Index)++] = Modulo;
}

static void BuildCopperList(UWORD* List)
{
    UWORD Index = 0;
    UBYTE WrapWaitInserted = 0;

    List[Index++] = 0x008E;
    List[Index++] = HAM_DIWSTRT;
    List[Index++] = 0x0090;
    List[Index++] = HAM_DIWSTOP;
    List[Index++] = 0x0092;
    List[Index++] = HAM_DDFSTRT;
    List[Index++] = 0x0094;
    List[Index++] = HAM_DDFSTOP;

    List[Index++] = 0x0100;
    List[Index++] = (UWORD)((HAM_DISPLAY_BPU << 12) | 0x0A00);
    List[Index++] = 0x0102;
    List[Index++] = 0x0000;
    List[Index++] = 0x0104;
    List[Index++] = 0x0000;
    List[Index++] = 0x0108;
    List[Index++] = HAM_REPEAT_MOD;
    List[Index++] = 0x010A;
    List[Index++] = HAM_REPEAT_MOD;

    List[Index++] = 0x0118;
    List[Index++] = HAM_CONTROL_WORD_P5;
    List[Index++] = 0x011A;
    List[Index++] = HAM_CONTROL_WORD_P6;

    CopperAppendBitplanePointerSlots(List, &Index);

    for (UWORD Color = 0; Color < 16; ++Color)
    {
        List[Index++] = 0x0180 + (Color << 1);
        List[Index++] = 0x0000;
    }

    // The Copper uses three contiguous runs: dynamic rows 0-25 from the
    // prepared buffer, half-rate cached rows 26-48, and direct slow-cache
    // rows 49-51.
    for (UWORD Row = 0; Row < (HAM_HALFRATE_START_ROW - 1); ++Row)
    {
        CopperAppendWait(List, &Index, (UWORD)(HAM_VPOS_START + (Row * HAM_PIXEL_SIZE) + (HAM_PIXEL_SIZE - 1)), &WrapWaitInserted);
        CopperAppendModulo(List, &Index, HAM_ADVANCE_MOD);
        CopperAppendWait(List, &Index, (UWORD)(HAM_VPOS_START + ((Row + 1) * HAM_PIXEL_SIZE)), &WrapWaitInserted);
        CopperAppendModulo(List, &Index, HAM_REPEAT_MOD);
    }

    CopperAppendWait(List, &Index, (UWORD)(HAM_VPOS_START + (HAM_HALFRATE_START_ROW * HAM_PIXEL_SIZE)), &WrapWaitInserted);
    CopperAppendBitplanePointerSlots(List, &Index);

    for (UWORD Row = HAM_HALFRATE_START_ROW; Row < (HAM_SLOW_START_ROW - 1); ++Row)
    {
        CopperAppendWait(List, &Index, (UWORD)(HAM_VPOS_START + (Row * HAM_PIXEL_SIZE) + (HAM_PIXEL_SIZE - 1)), &WrapWaitInserted);
        CopperAppendModulo(List, &Index, HAM_ADVANCE_MOD);
        CopperAppendWait(List, &Index, (UWORD)(HAM_VPOS_START + ((Row + 1) * HAM_PIXEL_SIZE)), &WrapWaitInserted);
        CopperAppendModulo(List, &Index, HAM_REPEAT_MOD);
    }

    CopperAppendWait(List, &Index, (UWORD)(HAM_VPOS_START + (HAM_SLOW_START_ROW * HAM_PIXEL_SIZE)), &WrapWaitInserted);
    CopperAppendBitplanePointerSlots(List, &Index);

    for (UWORD Row = HAM_SLOW_START_ROW; Row < (HAM_CACHE_START_ROW - 1); ++Row)
    {
        CopperAppendWait(List, &Index, (UWORD)(HAM_VPOS_START + (Row * HAM_PIXEL_SIZE) + (HAM_PIXEL_SIZE - 1)), &WrapWaitInserted);
        CopperAppendModulo(List, &Index, HAM_ADVANCE_MOD);
        CopperAppendWait(List, &Index, (UWORD)(HAM_VPOS_START + ((Row + 1) * HAM_PIXEL_SIZE)), &WrapWaitInserted);
        CopperAppendModulo(List, &Index, HAM_REPEAT_MOD);
    }


    List[Index++] = 0xFFFF;
    List[Index++] = 0xFFFE;
}

static void CopperWriteBitplanePointers(UWORD* List, UWORD Index, const UBYTE* Row, UWORD PlaneBytes)
{
    ULONG Ptr = (ULONG)Row;

    List[Index +  0] = WORD_HI(Ptr);
    List[Index +  2] = WORD_LO(Ptr);
    Ptr += PlaneBytes;
    List[Index +  4] = WORD_HI(Ptr);
    List[Index +  6] = WORD_LO(Ptr);
    Ptr += PlaneBytes;
    List[Index +  8] = WORD_HI(Ptr);
    List[Index + 10] = WORD_LO(Ptr);
    Ptr += PlaneBytes;
    List[Index + 12] = WORD_HI(Ptr);
    List[Index + 14] = WORD_LO(Ptr);
}

static void InitCopperDynamicPointers(UWORD* List, const UBYTE* DynamicFrame)
{
    CopperWriteBitplanePointers(List, HAM_COPPER_BPLPTR_WORD, DynamicFrame, HAM_DYNAMIC_PLANE_BYTES);
}

static void InitCopperSlowPointers(UWORD* List, const UBYTE* SlowFrame)
{
    CopperWriteBitplanePointers(List, HAM_COPPER_SLOW_BPLPTR_WORD, SlowFrame, HAM_SLOW_ROW_CACHE_PLANE_BYTES);
}

static void InitCopperHalfRatePointers(UWORD* List, const UWORD* HalfPointers)
{
    UWORD Index = HAM_COPPER_HALFRATE_BPLPTR_WORD;

    for (UWORD Plane = 0; Plane < 4; ++Plane)
    {
        List[Index] = *HalfPointers++;
        List[Index + 2] = *HalfPointers++;
        Index += 4;
    }
}

static void InitDisplay(void)
{
    ChipBlock = (UBYTE*)AllocMem(HAM_CHIP_BLOCK_BYTES, MEMF_CHIP | MEMF_CLEAR);
    HalfRowCache = ChipBlock;
    HamBuffers[0] = HalfRowCache + HAM_HALFRATE_ROW_CACHE_BYTES;
    HamBuffers[1] = HamBuffers[0] + HAM_DYNAMIC_BITMAP_BYTES;
    CopperLists[0] = (UWORD*)(HamBuffers[1] + HAM_DYNAMIC_BITMAP_BYTES);
    CopperLists[1] = (UWORD*)((UBYTE*)CopperLists[0] + HAM_COPPER_BYTES);

    BuildHalfRowCache();
    BuildCopperList(CopperLists[0]);
    BuildCopperList(CopperLists[1]);
    InitCopperDynamicPointers(CopperLists[0], HamBuffers[0]);
    InitCopperDynamicPointers(CopperLists[1], HamBuffers[1]);
    InitCopperHalfRatePointers(CopperLists[0], HalfPointerWords);
    InitCopperHalfRatePointers(CopperLists[1], HalfPointerWords);
    InitCopperSlowPointers(CopperLists[0], SlowRowCache);
    InitCopperSlowPointers(CopperLists[1], SlowRowCache);
}

// ---------------------------------------------------------------------
// Cleanup
// ---------------------------------------------------------------------

static void Cleanup_All(void)
{
    lwmf_ReleaseOS();

    FreeMem(ChipBlock, HAM_CHIP_BLOCK_BYTES);
    ChipBlock = NULL;
    HalfRowCache = NULL;
    HamBuffers[0] = NULL;
    HamBuffers[1] = NULL;
    CopperLists[0] = NULL;
    CopperLists[1] = NULL;

    FreeMem(SlowBlock, SLOW_BLOCK_BYTES);
    SlowBlock = NULL;
    FreeMem(SlowRowCache, HAM_SLOW_ROW_CACHE_BYTES);
    SlowRowCache = NULL;
    TextureCells = NULL;
    PairTables = NULL;
    FrameParams = NULL;
    HalfPointerWords = NULL;
    UOffsetTable = NULL;
    UOffsetTableMid = NULL;

    lwmf_CloseLibraries();
}

// ---------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------

int main(void)
{
    lwmf_LoadGraphicsLib();

    InitTexture();
    InitDisplay();

    const UWORD* const TextureCellsMid = TextureCells + 16384;
    const UBYTE* const UOffsetMid = UOffsetTableMid;
    const UBYTE* const PairTablesBase = PairTables;
    const struct HamFrameParams* Params = FrameParams;
    const UBYTE* SlowFrame = SlowRowCache;
    UBYTE* const Ham0 = HamBuffers[0];
    UBYTE* const Ham1 = HamBuffers[1];
    UWORD* const Copper0 = CopperLists[0];
    UWORD* const Copper1 = CopperLists[1];
    const UWORD* HalfPointers = HalfPointerWords;
    UBYTE Frame = 0;

    lwmf_TakeOverOS();
    InitHamBlitterCopyModeAsm();
    *COP1LC = (ULONG)Copper0;

    while (*CIAA_PRA & 0x40)
    {
        const WORD DuDx = Params->DuDx;
        const WORD DvDx = Params->DvDx;
        const WORD RowUDelta = Params->RowUDelta;
        const WORD RowVDelta = Params->RowVDelta;

        WaitHamLiveDoneAndSwitchCopperAsm(Copper1);
        DBG_COLOR(0x000);
        RenderHamLiveRowsAsm(Ham0, TextureCellsMid, UOffsetMid, PairTablesBase, Params->RowU, Params->RowV, DuDx, DvDx, RowUDelta, RowVDelta);
        CopyHamTemporalLowerRowsAsm(Ham0, Ham1);
        RenderHamTemporalUpperRowsAsm(Ham0, TextureCellsMid, UOffsetMid, PairTablesBase, Params->TemporalUpperU, Params->TemporalUpperV, DuDx, DvDx, RowUDelta, RowVDelta);
        UpdateHamCachedPointersAsm(Copper0, HalfPointers, SlowFrame);
        DBG_COLOR(0x0F0);

        ++Params;
        SlowFrame += HAM_SLOW_ROW_CACHE_FRAME_BYTES;

        {
            const WORD DuDxOdd = Params->DuDx;
            const WORD DvDxOdd = Params->DvDx;
            const WORD RowUDeltaOdd = Params->RowUDelta;
            const WORD RowVDeltaOdd = Params->RowVDelta;

            WaitHamLiveDoneAndSwitchCopperAsm(Copper0);
            DBG_COLOR(0x000);
            RenderHamLiveRowsAsm(Ham1, TextureCellsMid, UOffsetMid, PairTablesBase, Params->RowU, Params->RowV, DuDxOdd, DvDxOdd, RowUDeltaOdd, RowVDeltaOdd);
            CopyHamTemporalUpperRowsAsm(Ham1, Ham0);
            RenderHamTemporalLowerRowsAsm(Ham1, TextureCellsMid, UOffsetMid, PairTablesBase, Params->TemporalLowerU, Params->TemporalLowerV, DuDxOdd, DvDxOdd, RowUDeltaOdd, RowVDeltaOdd);
            UpdateHamCachedPointersAsm(Copper1, HalfPointers, SlowFrame);
            DBG_COLOR(0x0F0);
        }

        ++Params;
        SlowFrame += HAM_SLOW_ROW_CACHE_FRAME_BYTES;
        HalfPointers += HAM_HALFRATE_POINTER_WORDS;
        Frame += 2;

        if (Frame == 0)
        {
            Params = FrameParams;
            HalfPointers = HalfPointerWords;
            SlowFrame = SlowRowCache;
        }
    }

    Cleanup_All();
    return 0;
}
