//**********************************************************************
//* 4x4 Copperchunky Rotozoomer                                        *
//*                                                                    *
//* Register-recycled RGB12 Copper display. Full 320x256 interleaved   *
//* 4 bitplane pattern uses cycle-planned COLOR01-COLOR15 updates.     *
//* Each reused register is rewritten after its previous visible use.   *
//* Amiga 500 OCS, 512kb Chip + 512kb Slowmem                          *
//**********************************************************************

#include "lwmf/lwmf.h"

#define CC_COLS                                 40
#define CC_COLOR_REGISTER_COUNT                 15
#define CC_PIXEL_SIZE                           4
#define CC_ROWS                                 (SCREENHEIGHT / CC_PIXEL_SIZE)
#define CC_DISPLAY_WIDTH                        (CC_COLS * CC_PIXEL_SIZE)
#define CC_DISPLAY_START_X                      ((SCREENWIDTH - CC_DISPLAY_WIDTH) >> 1)
#define CC_DDF_SHIFT_BYTES                      (CC_DISPLAY_START_X >> 3)
#define CC_VPOS_START                           0x002C
#define CC_VPOS_STOP                            (CC_VPOS_START + SCREENHEIGHT)
#define CC_DIWSTRT                              (((CC_VPOS_START & 0xFF) << 8) | 0x0081)
#define CC_DIWSTOP                              (((CC_VPOS_STOP & 0xFF) << 8) | 0x00C1)
#define CC_FETCH_BYTES                          ((((CC_DISPLAY_WIDTH + 15) >> 4) << 1))
#define CC_DDFSTRT                              (0x0038 + (CC_DDF_SHIFT_BYTES << 2))
#define CC_DDFSTOP                              (0x00D0 - (CC_DDF_SHIFT_BYTES << 2))
#define CC_BPLCON0                              0x4200
#define CC_BPL_MOD                              (SCREENWIDTHTOTAL - CC_FETCH_BYTES)
#define CC_FRAME_COUNT                          256
#define CC_HALF_COLS                            (CC_COLS >> 1)
#define CC_HALF_ROWS                            (CC_ROWS >> 1)
#define CC_PREFILL_COLS                          CC_COLOR_REGISTER_COUNT
#define CC_COPPER_PREFILL_HPOS                   0x0031
#define CC_DISPLAY_HPOS_START                    0x0081
#define CC_COPPER_UPDATE_PHASE                   4
#define CC_COPPER_UPDATE_HPOS(c)                 (CC_DISPLAY_HPOS_START + ((((c) - CC_PREFILL_COLS) << 1) + CC_COPPER_UPDATE_PHASE))
#define CC_COPPER_LINE_WORDS                    (2 + (CC_PREFILL_COLS << 1) + ((CC_COLS - CC_PREFILL_COLS) << 2))
#define CC_COPPER_SETUP_WORDS                   66
#define CC_COPPER_WRAP_WORDS                    2
#define CC_COPPER_END_WORDS                     2
#define CC_COPPER_WORDS                         (CC_COPPER_SETUP_WORDS + (SCREENHEIGHT * CC_COPPER_LINE_WORDS) + CC_COPPER_WRAP_WORDS + CC_COPPER_END_WORDS)
#define CC_COPPER_BYTES                         (CC_COPPER_WORDS << 1)
#define CC_PATTERN_BYTES                        (SCREENWIDTHTOTAL * SCREENHEIGHT)
#define CC_TEXTURE_WIDTH                        128
#define CC_TEXTURE_HEIGHT                       128
#define CC_TEXTURE_SOURCE_PLANES                6
#define CC_TEXTURE_BYTES                        65536
#define CC_UOFFSET_TABLE_BYTES                  65536
#define CC_FRAME_PARAMS_BYTES                   (CC_FRAME_COUNT * 12)
#define CC_SLOW_BLOCK_BYTES                     (CC_TEXTURE_BYTES + CC_UOFFSET_TABLE_BYTES + CC_FRAME_PARAMS_BYTES)
#define CC_ZOOM_BASE                            256
#define CC_ZOOM_AMPLITUDE                       80
#define CC_CENTER_U                             0x4000
#define CC_CENTER_V                             0x4000
#define CC_PHASE_STEP                           1
#define CC_DEBUG_SOLID_TEST                     0

#define WORD_HI(v)                              ((UWORD)((ULONG)(v) >> 16))
#define WORD_LO(v)                              ((UWORD)((ULONG)(v) & 0xFFFF))
#define BPLPTH(p)                               (0x00E0 + ((p) << 2))
#define BPLPTL(p)                               (0x00E2 + ((p) << 2))
#define PHASE8(v)                               ((UBYTE)(v))
#define COLOR_REG(c)                            (0x0180 + ((c) << 1))
#define COPPER_LISTS_BYTES                      (CC_COPPER_BYTES * 2)
#define CHIP_BLOCK_BYTES                        (COPPER_LISTS_BYTES + CC_PATTERN_BYTES)

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

struct CCFrameParams
{
    WORD  DuDx;
    WORD  DvDx;
    UWORD RowU;
    UWORD RowV;
    WORD  RowUDelta;
    WORD  RowVDelta;
};

static UBYTE* SlowBlock;
static UWORD* TextureRGB12;
static UWORD* TextureRGB12Mid;
static UBYTE* UOffsetTable;
static UBYTE* UOffsetTableMid;
static struct CCFrameParams* FrameParams;
static UBYTE* ChipBlock;
static UWORD* CopperList0;
static UWORD* CopperList1;
static UBYTE* PatternPlanes;
static UWORD* CopperValueSlots0[SCREENHEIGHT][CC_COLS];
static UWORD* CopperValueSlots1[SCREENHEIGHT][CC_COLS];

static void CopperAppendWait(UWORD* List, UWORD* Index, UWORD VPos, UWORD HPos, UBYTE* Wrapped)
{
    if ((VPos > 0x00FF) && !(*Wrapped))
    {
        List[(*Index)++] = 0xFFDF;
        List[(*Index)++] = 0xFFFE;
        *Wrapped = 1;
    }

    List[(*Index)++] = (UWORD)(((VPos & 0xFF) << 8) | (HPos & 0xFE) | 1);
    List[(*Index)++] = 0xFFFE;
}

static void CopperAppendMove(UWORD* List, UWORD* Index, UWORD Reg, UWORD Value)
{
    List[(*Index)++] = Reg;
    List[(*Index)++] = Value;
}

static void CopperAppendBitplanePointers(UWORD* List, UWORD* Index, const UBYTE* Pattern)
{
    ULONG Ptr = (ULONG)Pattern;

    for (UWORD Plane = 0; Plane < NUMBEROFBITPLANES; ++Plane)
    {
        CopperAppendMove(List, Index, BPLPTH(Plane), WORD_HI(Ptr + (Plane * BYTESPERROW)));
        CopperAppendMove(List, Index, BPLPTL(Plane), WORD_LO(Ptr + (Plane * BYTESPERROW)));
    }
}

// Build a full 320x256 interleaved pattern, using the same memory layout as lwmf screen bitmaps.
// The Copper preloads COLOR01-COLOR15 before fetch and updates them one full cycle later.
static void BuildPatternPlanes(void)
{
    for (UWORD Row = 0; Row < SCREENHEIGHT; ++Row)
    {
        UBYTE* RowBase = PatternPlanes + ((ULONG)Row * SCREENWIDTHTOTAL);

        UBYTE Color = 1;

        for (UWORD Cell = 0; Cell < CC_COLS; ++Cell)
        {
            for (UWORD Pixel = 0; Pixel < CC_PIXEL_SIZE; ++Pixel)
            {
                const UWORD X = (UWORD)((Cell << 2) + Pixel);
                const UWORD Byte = X >> 3;
                const UBYTE Mask = (UBYTE)(0x80 >> (X & 7));

                for (UWORD Plane = 0; Plane < NUMBEROFBITPLANES; ++Plane)
                {
                    if (Color & (1 << Plane))
                    {
                        RowBase[(Plane * BYTESPERROW) + Byte] |= Mask;
                    }
                }
            }

            ++Color;
            if (Color > CC_COLOR_REGISTER_COUNT)
            {
                Color = 1;
            }
        }
    }
}

static void BuildCopperList(UWORD* List, UWORD* ValueSlots[SCREENHEIGHT][CC_COLS])
{
    UWORD Index = 0;
    UBYTE Wrapped = 0;

    CopperAppendMove(List, &Index, 0x008E, CC_DIWSTRT);
    CopperAppendMove(List, &Index, 0x0090, CC_DIWSTOP);
    CopperAppendMove(List, &Index, 0x0092, CC_DDFSTRT);
    CopperAppendMove(List, &Index, 0x0094, CC_DDFSTOP);

    CopperAppendMove(List, &Index, 0x0100, CC_BPLCON0);
    CopperAppendMove(List, &Index, 0x0102, 0x0000);
    CopperAppendMove(List, &Index, 0x0104, 0x0000);
    CopperAppendMove(List, &Index, 0x0108, CC_BPL_MOD);
    CopperAppendMove(List, &Index, 0x010A, CC_BPL_MOD);

    CopperAppendBitplanePointers(List, &Index, PatternPlanes);

    for (UWORD Color = 0; Color < 16; ++Color)
    {
        CopperAppendMove(List, &Index, COLOR_REG(Color), Color ? 0x0222 : 0x0000);
    }

    for (UWORD Line = 0; Line < SCREENHEIGHT; ++Line)
    {
        UBYTE Color = 1;

        CopperAppendWait(List, &Index, (UWORD)(CC_VPOS_START + Line), CC_COPPER_PREFILL_HPOS, &Wrapped);

        for (UWORD Cell = 0; Cell < CC_PREFILL_COLS; ++Cell)
        {
            ValueSlots[Line][Cell] = List + Index + 1;
            CopperAppendMove(List, &Index, COLOR_REG(Color), 0x0000);
            ++Color;
        }

        if (Color > CC_COLOR_REGISTER_COUNT)
        {
            Color = 1;
        }

        for (UWORD Cell = CC_PREFILL_COLS; Cell < CC_COLS; ++Cell)
        {
            CopperAppendWait(List, &Index, (UWORD)(CC_VPOS_START + Line), CC_COPPER_UPDATE_HPOS(Cell), &Wrapped);
            ValueSlots[Line][Cell] = List + Index + 1;
            CopperAppendMove(List, &Index, COLOR_REG(Color), 0x0000);
            ++Color;
            if (Color > CC_COLOR_REGISTER_COUNT)
            {
                Color = 1;
            }
        }
    }

    List[Index++] = 0xFFFF;
    List[Index++] = 0xFFFE;
}

static void BuildTextureFromHAM(const struct lwmf_Image* Image)
{
    const UWORD ByteColumns = CC_TEXTURE_WIDTH >> 3;
    const ULONG ImageRowBytes = Image->Image.BytesPerRow;
    UWORD BasePalette[16];

    for (UWORD i = 0; i < 16; ++i)
    {
        BasePalette[i] = (UWORD)(Image->CRegs[i] & 0x0FFF);
    }

    for (UWORD Y = 0; Y < CC_TEXTURE_HEIGHT; ++Y)
    {
        const ULONG PlaneRowOffset = (ULONG)Y * ImageRowBytes;
        const UBYTE* PlaneRows[CC_TEXTURE_SOURCE_PLANES];
        UWORD CurrentRGB = BasePalette[0];
        UWORD* Out = TextureRGB12 + ((ULONG)Y * CC_TEXTURE_WIDTH);
        UWORD* OutMirror = TextureRGB12 + (((ULONG)Y + CC_TEXTURE_HEIGHT) * CC_TEXTURE_WIDTH);

        for (UWORD Plane = 0; Plane < CC_TEXTURE_SOURCE_PLANES; ++Plane)
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
                *Out++ = OutRGB;
                *OutMirror++ = OutRGB;
            }
        }
    }
}

static void BuildUOffsetTable(void)
{
    for (ULONG i = 0; i < CC_UOFFSET_TABLE_BYTES; ++i)
    {
        UOffsetTable[(UWORD)(i + 32768)] = (UBYTE)((i >> 7) & 0xFE);
    }
}

static void BuildFrameParams(void)
{
    for (UWORD Frame = 0; Frame < CC_FRAME_COUNT; ++Frame)
    {
        const WORD SinA = (WORD)SinTab256[PHASE8(Frame)] - 32;
        const WORD CosA = (WORD)SinTab256[PHASE8(Frame + 64)] - 32;
        const WORD Zoom = CC_ZOOM_BASE + ((SinA * CC_ZOOM_AMPLITUDE) >> 5);
        const WORD DuDx = (CosA * Zoom) >> 5;
        const WORD DvDx = (SinA * Zoom) >> 5;
        const LONG CenterU = CC_CENTER_U + ((LONG)SinTab256[PHASE8(Frame * 3)] << 7);
        const LONG CenterV = CC_CENTER_V + ((LONG)SinTab256[PHASE8(Frame * 5)] << 7);
        const LONG OffsetU = (CC_HALF_COLS * DuDx) - (CC_HALF_ROWS * DvDx);
        const LONG OffsetV = (CC_HALF_COLS * DvDx) + (CC_HALF_ROWS * DuDx);

        FrameParams[Frame].DuDx = DuDx;
        FrameParams[Frame].DvDx = DvDx;
        FrameParams[Frame].RowU = (UWORD)(CenterU - OffsetU);
        FrameParams[Frame].RowV = (UWORD)(CenterV - OffsetV);
        FrameParams[Frame].RowUDelta = (WORD)(-((LONG)CC_COLS * DuDx) - DvDx);
        FrameParams[Frame].RowVDelta = (WORD)(DuDx - ((LONG)CC_COLS * DvDx));
    }
}

static void FillDebugCopper(UWORD* ValueSlots[SCREENHEIGHT][CC_COLS], UBYTE Phase)
{
    for (UWORD Row = 0; Row < CC_ROWS; ++Row)
    {
        for (UWORD Rep = 0; Rep < CC_PIXEL_SIZE; ++Rep)
        {
            UWORD Line = (UWORD)((Row << 2) + Rep);

            for (UWORD Cell = 0; Cell < CC_COLS; ++Cell)
            {
                const UWORD V = (UWORD)((Cell + Row + Phase) & 15);
                *ValueSlots[Line][Cell] = (UWORD)(((V & 15) << 8) | (((V + 5) & 15) << 4) | ((V + 10) & 15));
            }
        }
    }
}

static void RenderCopperChunkyFrameC(const UWORD* TextureMid, const UBYTE* UOffsetMid, UWORD* ValueSlots[SCREENHEIGHT][CC_COLS], const struct CCFrameParams* Params)
{
    WORD DuDx = Params->DuDx;
    WORD DvDx = Params->DvDx;
    UWORD RowU = Params->RowU;
    UWORD RowV = Params->RowV;
    WORD RowUDelta = Params->RowUDelta;
    WORD RowVDelta = Params->RowVDelta;

    for (UWORD Row = 0; Row < CC_ROWS; ++Row)
    {
        UWORD U = RowU;
        UWORD V = RowV;

        for (UWORD Cell = 0; Cell < CC_COLS; ++Cell)
        {
            UWORD Offset = V;
            ((UBYTE*)&Offset)[1] = UOffsetMid[U];
            UWORD RGB = TextureMid[Offset];

            for (UWORD Rep = 0; Rep < CC_PIXEL_SIZE; ++Rep)
            {
                *ValueSlots[(Row << 2) + Rep][Cell] = RGB;
            }

            U += DuDx;
            V += DvDx;
        }

        RowU = (UWORD)(U + RowUDelta);
        RowV = (UWORD)(V + RowVDelta);
    }
}

static void InitSlowData(void)
{
    extern UBYTE RotoImage[];
    extern UBYTE RotoImage_end[];
    struct lwmf_Image* Image = lwmf_LoadImageMem(RotoImage, (ULONG)(RotoImage_end - RotoImage));

    SlowBlock = (UBYTE*)lwmf_AllocCpuMem(CC_SLOW_BLOCK_BYTES, 0);
    TextureRGB12 = (UWORD*)SlowBlock;
    UOffsetTable = SlowBlock + CC_TEXTURE_BYTES;
    FrameParams = (struct CCFrameParams*)(SlowBlock + CC_TEXTURE_BYTES + CC_UOFFSET_TABLE_BYTES);
    TextureRGB12Mid = TextureRGB12 + 16384;
    UOffsetTableMid = UOffsetTable + 32768;

    BuildTextureFromHAM(Image);
    lwmf_DeleteImage(Image);
    BuildUOffsetTable();
    BuildFrameParams();
}

static void InitDisplay(void)
{
    ChipBlock = (UBYTE*)AllocMem(CHIP_BLOCK_BYTES, MEMF_CHIP | MEMF_CLEAR);
    CopperList0 = (UWORD*)ChipBlock;
    CopperList1 = (UWORD*)(ChipBlock + CC_COPPER_BYTES);
    PatternPlanes = ChipBlock + COPPER_LISTS_BYTES;

    BuildPatternPlanes();
    BuildCopperList(CopperList0, CopperValueSlots0);
    BuildCopperList(CopperList1, CopperValueSlots1);
}

static void CleanupAll(void)
{
    lwmf_ReleaseOS();
    FreeMem(ChipBlock, CHIP_BLOCK_BYTES);
    FreeMem(SlowBlock, CC_SLOW_BLOCK_BYTES);
    lwmf_CloseLibraries();
}

int main(void)
{
    UBYTE Phase = 0;
    UBYTE Flip = 0;

    lwmf_LoadGraphicsLib();
    InitSlowData();
    InitDisplay();
    lwmf_TakeOverOS();

#if CC_DEBUG_SOLID_TEST
    FillDebugCopper(CopperValueSlots0, 0);
    FillDebugCopper(CopperValueSlots1, 0);
#else
    RenderCopperChunkyFrameC(TextureRGB12Mid, UOffsetTableMid, CopperValueSlots0, FrameParams);
    RenderCopperChunkyFrameC(TextureRGB12Mid, UOffsetTableMid, CopperValueSlots1, FrameParams);
#endif

    *COP1LC = (ULONG)CopperList0;

    while (*CIAA_PRA & 0x40)
    {
        UWORD* DrawList = Flip ? CopperList0 : CopperList1;
        UWORD* (*DrawValues)[CC_COLS] = Flip ? CopperValueSlots0 : CopperValueSlots1;

        Phase = PHASE8(Phase + CC_PHASE_STEP);
#if CC_DEBUG_SOLID_TEST
        FillDebugCopper(DrawValues, Phase);
#else
        RenderCopperChunkyFrameC(TextureRGB12Mid, UOffsetTableMid, DrawValues, FrameParams + Phase);
#endif

        lwmf_WaitVertBlank();
        *COP1LC = (ULONG)DrawList;
        Flip ^= 1;
    }

    CleanupAll();
    return 0;
}
