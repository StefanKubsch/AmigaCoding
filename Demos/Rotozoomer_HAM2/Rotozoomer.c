//**********************************************************************
//* 4x4 HAM7 BPLDAT Quirk Rotozoomer                         *
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

// ---------------------------------------------------------------------
// Debugging
// ---------------------------------------------------------------------

#define DEBUG 1

#if DEBUG
#define DBG_COLOR(c) (*COLOR00 = (c))
#else
#define DBG_COLOR(c) do {} while (0)
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
#define TEXTURE_CELL_BYTES      ((ULONG)TEXTURE_WIDTH * TEXTURE_EXPANDED_HEIGHT * sizeof(UWORD))
#define TEXTURE_DUAL_BYTES      (TEXTURE_CELL_BYTES * 2)
#define PAIR_TABLE_BYTES        (4096 * 8)

#define HAM_COLUMNS             48
#define HAM_ROWS                48
#define HAM_PIXEL_SIZE          4
#define HAM_DISPLAY_WIDTH       (HAM_COLUMNS * HAM_PIXEL_SIZE)
#define HAM_DISPLAY_HEIGHT      (HAM_ROWS * HAM_PIXEL_SIZE)
#define HAM_FETCH_BYTES         (HAM_DISPLAY_WIDTH >> 3)
#define HAM_PLANE_BYTES         (HAM_FETCH_BYTES * HAM_ROWS)
#define HAM_BITMAP_BYTES        (HAM_PLANE_BYTES * 4)
#define HAM_HALF_COLUMNS        (HAM_COLUMNS / 2)
#define HAM_HALF_ROWS           (HAM_ROWS / 2)

#define HAM_SCREEN_WIDTH        320
#define HAM_SCREEN_HEIGHT       256
#define HAM_START_X             ((HAM_SCREEN_WIDTH - HAM_DISPLAY_WIDTH) / 2)
#define HAM_PAL_VPOS_TOP        0x2C
#define HAM_VPOS_START          (HAM_PAL_VPOS_TOP + ((HAM_SCREEN_HEIGHT - HAM_DISPLAY_HEIGHT) / 2))
#define HAM_VPOS_STOP           (HAM_VPOS_START + HAM_DISPLAY_HEIGHT)
#define HAM_DIWSTRT             ((UWORD)(((HAM_VPOS_START & 0xFF) << 8) | 0x0081))
#define HAM_DIWSTOP             ((UWORD)(((HAM_VPOS_STOP & 0xFF) << 8) | 0x00C1))
#define HAM_DDF_SHIFT_BYTES     (HAM_START_X >> 3)
#define HAM_DDFSTRT             (0x0038 + (HAM_DDF_SHIFT_BYTES * 4))
#define HAM_DDFSTOP             (0x00D0 - (HAM_DDF_SHIFT_BYTES * 4))
#define HAM_REPEAT_MOD          ((UWORD)(-(WORD)HAM_FETCH_BYTES))
#define HAM_ADVANCE_MOD         0

#define HAM_DISPLAY_BPU         7
#define HAM_CONTROL_WORD_P5     0x3333
#define HAM_CONTROL_WORD_P6     0x6666

#define HAM_ZOOM_BASE           256
#define HAM_ZOOM_AMPLITUDE      96
#define HAM_ANGLE_PHASE_STEP    2
#define HAM_FRAME_HOLD          1
#define HAM_CENTER_U            0x4000
#define HAM_CENTER_V            0x4000
#define HAM_FRAME_COUNT         256
#define TEXTURE_SOURCE_PLANES   6

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
static UWORD* TextureCellsLow = NULL;
static UWORD* TextureCellsHigh = NULL;
static UBYTE* PairTables = NULL;
static UBYTE* HamBuffers[2] = { NULL, NULL };
static UWORD* CopperLists[2] = { NULL, NULL };
static UBYTE* ChipBlock = NULL;
static ULONG ChipBlockBytes = 0;
static ULONG CopperBytes = 0;
static UWORD BasePalette[16];
static const UBYTE ZeroPlaneRow[128] = { 0 };

struct HamFrameParams
{
    WORD  DuDx;
    WORD  DvDx;
};

struct HamRowStart
{
    UWORD RowU;
    UWORD RowV;
};

static struct HamFrameParams* FrameParams = NULL;
static struct HamRowStart* FrameRowStarts = NULL;
static UBYTE* UOffsetTable = NULL;
static UBYTE* UOffsetTableMid = NULL;
#define FRAME_PARAMS_BYTES      (HAM_FRAME_COUNT * sizeof(struct HamFrameParams))
#define FRAME_ROW_START_BYTES   (HAM_FRAME_COUNT * HAM_ROWS * sizeof(struct HamRowStart))
#define UOFFSET_TABLE_BYTES     65536
#define SLOW_BLOCK_BYTES        (TEXTURE_DUAL_BYTES + PAIR_TABLE_BYTES + FRAME_PARAMS_BYTES + UOFFSET_TABLE_BYTES)

void RenderHamFrameAsm(__reg("a0") UBYTE* Buffer,
                       __reg("a1") const UWORD* TextureCellsHighMid,
                       __reg("a2") const UBYTE* UOffsetTableMid,
                       __reg("a3") const UBYTE* PairTables,
                       __reg("d4") const struct HamRowStart* RowStarts,
                       __reg("d5") const UWORD* TextureCellsLowMid,
                       __reg("d0") WORD DuDx,
                       __reg("d1") WORD DvDx);

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
        const UBYTE* PlaneRows[8];
        UWORD CurrentRGB = BasePalette[0];
        UWORD* OutLow = TextureCellsLow + ((ULONG)Y * TEXTURE_WIDTH);
        UWORD* OutLowMirror = TextureCellsLow + (((ULONG)Y + TEXTURE_HEIGHT) * TEXTURE_WIDTH);
        UWORD* OutHigh = TextureCellsHigh + ((ULONG)Y * TEXTURE_WIDTH);
        UWORD* OutHighMirror = TextureCellsHigh + (((ULONG)Y + TEXTURE_HEIGHT) * TEXTURE_WIDTH);

        for (UWORD Plane = 0; Plane < TEXTURE_SOURCE_PLANES; ++Plane)
        {
            PlaneRows[Plane] = (const UBYTE*)Image->Image.Planes[Plane] + PlaneRowOffset;
        }

        PlaneRows[6] = ZeroPlaneRow;
        PlaneRows[7] = ZeroPlaneRow;

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
                    ((P0 >> 7) & 0x01) |
                    ((P1 >> 6) & 0x02) |
                    ((P2 >> 5) & 0x04) |
                    ((P3 >> 4) & 0x08) |
                    ((P4 >> 3) & 0x10) |
                    ((P5 >> 2) & 0x20) |
                    ((P6 >> 1) & 0x40) |
                    (P7 & 0x80);
                const UBYTE Data = Pixel & 0x0F;
                const UBYTE Ctrl = Pixel >> 4;
                UWORD OutRGB;

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
                const UWORD LowIndex = (UWORD)((OutRGB << 2) + 16384);
                const UWORD HighIndex = (UWORD)(OutRGB << 2);

                *OutLow++ = LowIndex;
                *OutLowMirror++ = LowIndex;
                *OutHigh++ = HighIndex;
                *OutHighMirror++ = HighIndex;
            }
        }
    }
}

static void BuildPairTables(void)
{
    for (UWORD Color = 0; Color < 4096; ++Color)
    {
        const UBYTE R = (UBYTE)((Color >> 8) & 0x0F);
        const UBYTE G = (UBYTE)((Color >> 4) & 0x0F);
        const UBYTE B = (UBYTE)(Color & 0x0F);

        for (UBYTE Plane = 0; Plane < 4; ++Plane)
        {
            const UBYTE Nibble =
                (UBYTE)((((R >> Plane) & 1) << 2) |
                        (((G >> Plane) & 1) << 1) |
                        ((B >> Plane) & 1));

            const UWORD Offset = (UWORD)((Color << 2) + Plane);

            PairTables[Offset] = (UBYTE)(Nibble << 4);
            PairTables[16384 + Offset] = Nibble;
        }
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
        const WORD DuDy = -DvDx;
        const WORD DvDy = DuDx;
        const WORD MoveU = (WORD)SinTab256[PHASE8(Frame)] - 32;
        const WORD MoveV = (WORD)SinTab256[PHASE8(Frame + 64)] - 32;
        const LONG CenterU = HAM_CENTER_U + ((LONG)MoveU << 8);
        const LONG CenterV = HAM_CENTER_V + ((LONG)MoveV << 8);
        const LONG OffsetU = (HAM_HALF_COLUMNS * DuDx) + (HAM_HALF_ROWS * DuDy);
        const LONG OffsetV = (HAM_HALF_COLUMNS * DvDx) + (HAM_HALF_ROWS * DvDy);

        UWORD RowU = (UWORD)(CenterU - OffsetU);
        UWORD RowV = (UWORD)(CenterV - OffsetV);
        struct HamRowStart* RowStart = FrameRowStarts + ((ULONG)Frame * HAM_ROWS);

        FrameParams[Frame].DuDx = DuDx;
        FrameParams[Frame].DvDx = DvDx;

        for (UWORD Row = 0; Row < HAM_ROWS; ++Row)
        {
            RowStart[Row].RowU = RowU;
            RowStart[Row].RowV = RowV;
            RowU += DuDy;
            RowV += DvDy;
        }
    }
}

static void InitTexture(void)
{
    struct lwmf_Image* Image = lwmf_LoadImage(TEXTURE_FILENAME);

    SlowBlock = (UBYTE*)lwmf_AllocCpuMem(SLOW_BLOCK_BYTES, MEMF_CLEAR);
    FrameRowStarts = (struct HamRowStart*)lwmf_AllocCpuMem(FRAME_ROW_START_BYTES, MEMF_CLEAR);
    TextureCellsLow = (UWORD*)SlowBlock;
    TextureCellsHigh = (UWORD*)(SlowBlock + TEXTURE_CELL_BYTES);
    PairTables = SlowBlock + TEXTURE_DUAL_BYTES;
    FrameParams = (struct HamFrameParams*)(SlowBlock + TEXTURE_DUAL_BYTES + PAIR_TABLE_BYTES);
    UOffsetTable = SlowBlock + TEXTURE_DUAL_BYTES + PAIR_TABLE_BYTES + FRAME_PARAMS_BYTES;
    UOffsetTableMid = UOffsetTable + 32768;
    BuildTextureRGB4FromHAM(Image);
    BuildPairTables();
    BuildUOffsetTable();
    BuildFrameParams();

    lwmf_DeleteImage(Image);
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

static UWORD CountCopperWords(void)
{
    UWORD Count = 0;
    UBYTE WrapWaitInserted = 0;

    // Header: DIWSTRT/DIWSTOP/DDFSTRT/DDFSTOP
    Count += 8;
    // BPLCON0/1/2
    Count += 6;
    // BPL1MOD/BPL2MOD
    Count += 4;
    // BPL5DAT/BPL6DAT
    Count += 4;
    // 4 plane pointers
    Count += 16;
    // 16 palette entries
    Count += 32;

    for (UWORD Line = 3; (Line + 1) < HAM_DISPLAY_HEIGHT; Line += 4)
    {
        const UWORD VPos1 = (UWORD)(HAM_VPOS_START + Line);
        const UWORD VPos2 = (UWORD)(HAM_VPOS_START + Line + 1);

        if ((VPos1 > 0x00FF) && !WrapWaitInserted)
        {
            Count += 2; // wrap-wait pair
            WrapWaitInserted = 1;
        }
        Count += 6; // WAIT + two MOD writes

        if ((VPos2 > 0x00FF) && !WrapWaitInserted)
        {
            Count += 2;
            WrapWaitInserted = 1;
        }
        Count += 6;
    }

    Count += 2; // end-of-list WAIT
    return Count;
}

static void BuildCopperList(UWORD* List, UBYTE Buffer)
{
    UWORD Index = 0;
    UBYTE WrapWaitInserted = 0;
    const ULONG BasePtr = (ULONG)HamBuffers[Buffer];

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

    for (UWORD Plane = 0; Plane < 4; ++Plane)
    {
        const ULONG PlanePtr = BasePtr + (ULONG)Plane * HAM_PLANE_BYTES;

        List[Index++] = BPLPTH(Plane);
        List[Index++] = WORD_HI(PlanePtr);
        List[Index++] = BPLPTL(Plane);
        List[Index++] = WORD_LO(PlanePtr);
    }

    for (UWORD Color = 0; Color < 16; ++Color)
    {
        List[Index++] = 0x0180 + (Color << 1);
        List[Index++] = 0x0000;
    }

    for (UWORD Line = 3; (Line + 1) < HAM_DISPLAY_HEIGHT; Line += 4)
    {
        CopperAppendWait(List, &Index, (UWORD)(HAM_VPOS_START + Line), &WrapWaitInserted);
        List[Index++] = 0x0108;
        List[Index++] = HAM_ADVANCE_MOD;
        List[Index++] = 0x010A;
        List[Index++] = HAM_ADVANCE_MOD;

        CopperAppendWait(List, &Index, (UWORD)(HAM_VPOS_START + Line + 1), &WrapWaitInserted);
        List[Index++] = 0x0108;
        List[Index++] = HAM_REPEAT_MOD;
        List[Index++] = 0x010A;
        List[Index++] = HAM_REPEAT_MOD;
    }

    List[Index++] = 0xFFFF;
    List[Index++] = 0xFFFE;
}

static void InitDisplay(void)
{
    const UWORD CopperListWords = CountCopperWords();
    CopperBytes = (ULONG)CopperListWords * sizeof(UWORD);
    ChipBlockBytes = (HAM_BITMAP_BYTES * 2) + (CopperBytes * 2);

    ChipBlock = (UBYTE*)AllocMem(ChipBlockBytes, MEMF_CHIP | MEMF_CLEAR);
    HamBuffers[0] = ChipBlock;
    HamBuffers[1] = ChipBlock + HAM_BITMAP_BYTES;
    CopperLists[0] = (UWORD*)(ChipBlock + (HAM_BITMAP_BYTES * 2));
    CopperLists[1] = (UWORD*)((UBYTE*)CopperLists[0] + CopperBytes);

    BuildCopperList(CopperLists[0], 0);
    BuildCopperList(CopperLists[1], 1);
}

// ---------------------------------------------------------------------
// Cleanup
// ---------------------------------------------------------------------

static void Cleanup_All(void)
{
    lwmf_ReleaseOS();

    FreeMem(ChipBlock, ChipBlockBytes);
    ChipBlock = NULL;

    FreeMem(FrameRowStarts, FRAME_ROW_START_BYTES);
    FrameRowStarts = NULL;

    FreeMem(SlowBlock, SLOW_BLOCK_BYTES);
    SlowBlock = NULL;

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

    lwmf_TakeOverOS();
    *COP1LC = (ULONG)CopperLists[0];

    UBYTE DrawBuffer = 1;
    UBYTE Frame = 1;

    while (*CIAA_PRA & 0x40)
    {
        const struct HamFrameParams* Params = &FrameParams[Frame];

        RenderHamFrameAsm(HamBuffers[DrawBuffer], TextureCellsHigh + 16384, UOffsetTableMid, PairTables, FrameRowStarts + ((ULONG)Frame * HAM_ROWS), TextureCellsLow + 16384, Params->DuDx, Params->DvDx);

        *COP1LC = (ULONG)CopperLists[DrawBuffer];

        DBG_COLOR(0x00F);
        lwmf_WaitVertBlank();
        DBG_COLOR(0x000);

        DrawBuffer ^= 1;
        ++Frame;
    }

    Cleanup_All();
    return 0;
}
