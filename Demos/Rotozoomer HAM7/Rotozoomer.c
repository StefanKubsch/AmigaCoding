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
//* Must be booted from ADF/Disk, since memory access is critical      *
//* Quit with mouse click                                              *
//**********************************************************************

#include "lwmf/lwmf.h"
#include "Rotozoomer_shared.h"

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

static UWORD* TextureCells = NULL;
static UBYTE* PairTables = NULL;
static UBYTE* HalfFrameCacheBlock = NULL;
static UBYTE* HamBuffer0 = NULL;
static UWORD* CopperList0 = NULL;

struct HamFrameParams
{
    WORD  DuDx;
    WORD  DvDx;
    UWORD RowU;
    UWORD RowV;
};

struct HamMainLoopContext
{
    const UWORD* TextureCellsMid;
    const UBYTE* UOffsetMid;
    const UBYTE* PairTablesBase;
    const struct HamFrameParams* FrameParams;
    const UBYTE* HalfFrameCacheBase;
    UBYTE* Ham0;
    UBYTE* Ham1;
    UWORD* Copper0;
    UWORD* Copper1;
};

static struct HamFrameParams* FrameParams = NULL;
static UBYTE* UOffsetTable = NULL;
static UBYTE* UOffsetTableMid = NULL;
#define FRAME_PARAMS_BYTES      (HAM_FRAME_COUNT * sizeof(struct HamFrameParams))
#define UOFFSET_TABLE_BYTES     65536
#define SLOW_BLOCK_BYTES        (TEXTURE_CELL_BYTES + PAIR_TABLE_BYTES + FRAME_PARAMS_BYTES + UOFFSET_TABLE_BYTES)
#define DISPLAY_BLOCK_BYTES     HAM_CHIP_BLOCK_BYTES

void InitHamBlitterCopyModeAsm(void);
void RenderHamHalfRowsAsm(__reg("a0") UBYTE* Buffer, __reg("a1") const UWORD* TextureCellsMid, __reg("a2") const UBYTE* UOffsetTableMid, __reg("a3") const UBYTE* PairTables, __reg("d0") UWORD RowU, __reg("d1") UWORD RowV, __reg("d2") WORD DuDx, __reg("d3") WORD DvDx, __reg("d6") WORD RowUDelta, __reg("d7") WORD RowVDelta);
void RunHamMainLoopAsm(__reg("a0") const struct HamMainLoopContext* Context);

// ---------------------------------------------------------------------
// Texture conversion
// ---------------------------------------------------------------------

static void BuildTextureRGB4FromHAM(const struct lwmf_Image* Image)
{
    const UWORD ByteColumns = TEXTURE_SOURCE_WIDTH >> 3;
    const ULONG ImageRowBytes = Image->Image.BytesPerRow;
    UWORD BasePalette[16];

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
        const WORD SinA = (WORD)SinTab256[PHASE8(Frame)] - 32;
        const WORD CosA = (WORD)SinTab256[PHASE8(Frame + 64)] - 32;
        const WORD Zoom = HAM_ZOOM_BASE + ((SinA * HAM_ZOOM_AMPLITUDE) >> 5);
        const WORD DuDx = (CosA * Zoom) >> 5;
        const WORD DvDx = (SinA * Zoom) >> 5;
        const LONG CenterU = HAM_CENTER_U + ((LONG)SinA << 8);
        const LONG CenterV = HAM_CENTER_V + ((LONG)CosA << 8);
        const LONG OffsetU = (HAM_HALF_COLUMNS * DuDx) - (HAM_HALF_ROWS * DvDx);
        const LONG OffsetV = (HAM_HALF_COLUMNS * DvDx) + (HAM_HALF_ROWS * DuDx);

        const UWORD RowU = (UWORD)(CenterU - OffsetU);
        const UWORD RowV = (UWORD)(CenterV - OffsetV);

        FrameParams[Frame].DuDx = DuDx;
        FrameParams[Frame].DvDx = DvDx;
        FrameParams[Frame].RowU = RowU;
        FrameParams[Frame].RowV = RowV;
    }
}

static void BuildHalfRowCache(void)
{
    const UWORD* const TextureCellsMid = TextureCells + 16384;
    const UBYTE* const UOffsetMid = UOffsetTableMid;
    const UBYTE* const PairTablesBase = PairTables;

    for (UWORD Frame = 0; Frame < HAM_FRAME_COUNT; Frame += 2)
    {
        UBYTE* Bitmap = HalfFrameCacheBlock + ((ULONG)(Frame >> 1) * HAM_HALFRATE_ROW_CACHE_FRAME_BYTES);
        const struct HamFrameParams* Params = FrameParams + Frame;
        const WORD RowUDelta = (WORD)(-((LONG)(HAM_COLUMNS - 1) * Params->DuDx) - Params->DvDx);
        const WORD RowVDelta = (WORD)(Params->DuDx - ((LONG)(HAM_COLUMNS - 1) * Params->DvDx));
        const UWORD HalfRowU = (UWORD)(Params->RowU - ((LONG)HAM_HALFRATE_START_ROW * Params->DvDx));
        const UWORD HalfRowV = (UWORD)(Params->RowV + ((LONG)HAM_HALFRATE_START_ROW * Params->DuDx));

        RenderHamHalfRowsAsm(Bitmap, TextureCellsMid, UOffsetMid, PairTablesBase, HalfRowU, HalfRowV, Params->DuDx, Params->DvDx, RowUDelta, RowVDelta);
    }
}

static void InitTexture(void)
{
    struct lwmf_Image* Image = lwmf_LoadImage(TEXTURE_FILENAME);
    UBYTE* Base = (UBYTE*)lwmf_AllocCpuMem(SLOW_BLOCK_BYTES, 0);

    TextureCells = (UWORD*)Base;
    PairTables = Base + TEXTURE_CELL_BYTES;
    FrameParams = (struct HamFrameParams*)(Base + TEXTURE_CELL_BYTES + PAIR_TABLE_BYTES);
    UOffsetTable = Base + TEXTURE_CELL_BYTES + PAIR_TABLE_BYTES + FRAME_PARAMS_BYTES;
    UOffsetTableMid = UOffsetTable + 32768;
    BuildTextureRGB4FromHAM(Image);
    lwmf_DeleteImage(Image);

    BuildPairTables();
    BuildUOffsetTable();
    BuildFrameParams();
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

    // Program the display window and fetch timing for the centered HAM area.
    List[Index++] = 0x008E;
    List[Index++] = HAM_DIWSTRT;
    List[Index++] = 0x0090;
    List[Index++] = HAM_DIWSTOP;
    List[Index++] = 0x0092;
    List[Index++] = HAM_DDFSTRT;
    List[Index++] = 0x0094;
    List[Index++] = HAM_DDFSTOP;

    // Enable the 7-plane HAM display, clear both scroll registers, and start with
    // the "repeat this fetched row" modulo that stretches one rendered cell row over
    // HAM_PIXEL_SIZE scanlines until the Copper explicitly switches to advance mode.
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

    // Feed BPL5DAT/BPL6DAT with the fixed HAM control-bit patterns used by the renderer:
    // 0x3333 selects the "modify green/blue" pattern and 0x6666 the complementary control bits.
    List[Index++] = 0x0118;
    List[Index++] = HAM_CONTROL_WORD_P5;
    List[Index++] = 0x011A;
    List[Index++] = HAM_CONTROL_WORD_P6;

    // Reserve the first 4-plane pointer block. InitDisplay() patches this block to the
    // currently active dynamic bitmap (buffer 0 or buffer 1) before the list is used.
    CopperAppendBitplanePointerSlots(List, &Index);

    // Clear COLOR00-COLOR15 because the texture conversion already resolves RGB4 values.
    for (UWORD Color = 0; Color < 16; ++Color)
    {
        List[Index++] = 0x0180 + (Color << 1);
        List[Index++] = 0x0000;
    }

    // For the dynamic top band, every cell row is shown four times vertically:
    // at the end of the visible scanline group we set modulo 0 once to advance to the
    // next stored row, then immediately restore HAM_REPEAT_MOD so the next three lines
    // keep rereading that same stored row.
    for (UWORD Row = 0; Row < (HAM_HALFRATE_START_ROW - 1); ++Row)
    {
        CopperAppendWait(List, &Index, (UWORD)(HAM_VPOS_START + (Row * HAM_PIXEL_SIZE) + (HAM_PIXEL_SIZE - 1)), &WrapWaitInserted);
        CopperAppendModulo(List, &Index, HAM_ADVANCE_MOD);
        CopperAppendWait(List, &Index, (UWORD)(HAM_VPOS_START + ((Row + 1) * HAM_PIXEL_SIZE)), &WrapWaitInserted);
        CopperAppendModulo(List, &Index, HAM_REPEAT_MOD);
    }

    // At the split line, switch the 4-plane pointers from the live dynamic bitmap to the
    // cached lower-band bitmap. InitDisplay() and the main loop patch this second pointer
    // block to the current half-rate cache frame.
    CopperAppendWait(List, &Index, (UWORD)(HAM_VPOS_START + (HAM_HALFRATE_START_ROW * HAM_PIXEL_SIZE)), &WrapWaitInserted);
    CopperAppendBitplanePointerSlots(List, &Index);

    // The lower cached band uses the same vertical expansion pattern: advance once per
    // cell row, then immediately switch back to the repeat modulo so one cached source
    // row still occupies HAM_PIXEL_SIZE scanlines on screen.
    for (UWORD Row = HAM_HALFRATE_START_ROW; Row < (HAM_ROWS - 1); ++Row)
    {
        CopperAppendWait(List, &Index, (UWORD)(HAM_VPOS_START + (Row * HAM_PIXEL_SIZE) + (HAM_PIXEL_SIZE - 1)), &WrapWaitInserted);
        CopperAppendModulo(List, &Index, HAM_ADVANCE_MOD);
        CopperAppendWait(List, &Index, (UWORD)(HAM_VPOS_START + ((Row + 1) * HAM_PIXEL_SIZE)), &WrapWaitInserted);
        CopperAppendModulo(List, &Index, HAM_REPEAT_MOD);
    }

    // Finish the list with the standard Copper stop marker.
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

static void InitDisplay(void)
{
    UBYTE* HamBuffer1;
    UWORD* CopperList1;

    // Allocate the persistent chip-memory blocks: cached half-rate frames and the live display/copper area.
    HalfFrameCacheBlock = (UBYTE*)AllocMem(HAM_HALFRATE_ROW_CACHE_BYTES, MEMF_CHIP);
    HamBuffer0 = (UBYTE*)AllocMem(DISPLAY_BLOCK_BYTES, MEMF_CHIP | MEMF_CLEAR);

    // The chip block is packed as: dynamic buffer 0, dynamic buffer 1, copper list 0,
    // copper list 1. This keeps all flip-related display state in one contiguous allocation.
    HamBuffer1 = HamBuffer0 + HAM_DYNAMIC_BITMAP_BYTES;
    CopperList0 = (UWORD*)(HamBuffer1 + HAM_DYNAMIC_BITMAP_BYTES);
    CopperList1 = (UWORD*)((UBYTE*)CopperList0 + HAM_COPPER_BYTES);

    // Build the cached lower-band bitmaps, then create two copper lists for buffer flipping.
    BuildHalfRowCache();
    BuildCopperList(CopperList0);
    BuildCopperList(CopperList1);

    // Patch pointer block 0 to the live top-band buffers and pointer block 1 to the first
    // cached lower-band frame. The main loop later rewrites only the cached pointer block
    // when it advances to the next half-rate frame.
    CopperWriteBitplanePointers(CopperList0, HAM_COPPER_BPLPTR_WORD, HamBuffer0, HAM_DYNAMIC_PLANE_BYTES);
    CopperWriteBitplanePointers(CopperList1, HAM_COPPER_BPLPTR_WORD, HamBuffer1, HAM_DYNAMIC_PLANE_BYTES);
    CopperWriteBitplanePointers(CopperList0, HAM_COPPER_HALFRATE_BPLPTR_WORD, HalfFrameCacheBlock, HAM_HALFRATE_ROW_CACHE_PLANE_BYTES);
    CopperWriteBitplanePointers(CopperList1, HAM_COPPER_HALFRATE_BPLPTR_WORD, HalfFrameCacheBlock, HAM_HALFRATE_ROW_CACHE_PLANE_BYTES);
}

// ---------------------------------------------------------------------
// Cleanup
// ---------------------------------------------------------------------

static void Cleanup_All(void)
{
    lwmf_ReleaseOS();

    FreeMem(HamBuffer0, DISPLAY_BLOCK_BYTES);
    FreeMem(HalfFrameCacheBlock, HAM_HALFRATE_ROW_CACHE_BYTES);
    FreeMem(TextureCells, SLOW_BLOCK_BYTES);

    lwmf_CloseLibraries();
}

// ---------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------

int main(void)
{
    UBYTE* HamBuffer1;
    UWORD* CopperList1;

    lwmf_LoadGraphicsLib();
    InitTexture();
    lwmf_TakeOverOS();
    InitDisplay();

    HamBuffer1 = HamBuffer0 + HAM_DYNAMIC_BITMAP_BYTES;
    CopperList1 = (UWORD*)((UBYTE*)CopperList0 + HAM_COPPER_BYTES);

    struct HamMainLoopContext MainLoopContext;
    MainLoopContext.TextureCellsMid = TextureCells + 16384;
    MainLoopContext.UOffsetMid = UOffsetTableMid;
    MainLoopContext.PairTablesBase = PairTables;
    MainLoopContext.FrameParams = FrameParams;
    MainLoopContext.HalfFrameCacheBase = HalfFrameCacheBlock;
    MainLoopContext.Ham0 = HamBuffer0;
    MainLoopContext.Ham1 = HamBuffer1;
    MainLoopContext.Copper0 = CopperList0;
    MainLoopContext.Copper1 = CopperList1;

    InitHamBlitterCopyModeAsm();
    *COP1LC = (ULONG)MainLoopContext.Copper0;
    RunHamMainLoopAsm(&MainLoopContext);

    Cleanup_All();
    return 0;
}
