//**********************************************************************
//* 4x4 HAM7 Rotozoomer                                                *
//*                                                                    *
//* Working HAM7 baseline with assembler row-swap and blitter extract.             *
//*                                                                    *
//* Proven so far:                                                     *
//*   - sampler / UV / rotation                                        *
//*   - phase-0 HAM7 encoder (RGBB)                                    *
//*   - direct CPU planar output                                       *
//*   - scrambled-word layout                                          *
//*   - blitter extract stage                                          *
//*                                                                    *
//* Still intentionally bypassed for now:                              *
//*   - blitter 8x2 swap stage                                         *
//*                                                                    *
//* This build therefore uses:                                         *
//*   - CPU sample + phase-0 HAM7 encode to scrambled words            *
//*   - assembler row-swap into the proven ChunkyTmp layout                  *
//*   - blitter extract into the 4 DMA bitplanes                       *
//*   - 4x vertical repeat by row copy                                 *
//*                                                                    *
//* Target: Amiga 500 OCS, 68000, 512k Chip + 512k Slow                *
//* Project style: C99 / vbcc + vasm, lwmf framework                   *
//**********************************************************************
#include "lwmf/lwmf.h"
#include <stddef.h>

extern void RunC2PExtractAsm(__reg("a0") const UWORD* Temp,
                            __reg("a1") UBYTE* Planar);
extern void CpuSwapScrambledRowAsm(__reg("a0") const UWORD* ScrambledRow,
                                   __reg("a1") UWORD* TempRow);

#define DEBUG 1
#if DEBUG
#define DBG_COLOR(c) (*COLOR00 = (c))
#else
#define DBG_COLOR(c) ((void)0)
#endif

#define TEXTURE_FILENAME                "gfx/128x128_ham.iff"
#define TEXTURE_SOURCE_WIDTH            128
#define TEXTURE_SOURCE_HEIGHT           128
#define TEXTURE_WIDTH                   TEXTURE_SOURCE_WIDTH
#define TEXTURE_HEIGHT                  TEXTURE_SOURCE_HEIGHT
#define TEXTURE_WORD_COUNT              ((ULONG)TEXTURE_WIDTH * (ULONG)TEXTURE_HEIGHT)

#define ROTO_COLUMNS                    28
#define ROTO_ROWS                       48
#define ROTO_PIXEL_SCALE                4
#define ROTO_DISPLAY_WIDTH              (ROTO_COLUMNS * ROTO_PIXEL_SCALE)
#define ROTO_DISPLAY_HEIGHT             (ROTO_ROWS * ROTO_PIXEL_SCALE)
#define ROTO_HALF_COLUMNS               (ROTO_COLUMNS / 2)
#define ROTO_HALF_ROWS                  (ROTO_ROWS / 2)

#define ROTO_SCREEN_WIDTH               320
#define ROTO_SCREEN_HEIGHT              256
#define ROTO_DMA_BITPLANES              4
#define HAM_DISPLAY_BPU                 7
#define HAM_BPLCON0                     ((HAM_DISPLAY_BPU << 12) | 0x0A00)
#define HAM_CONTROL_WORD_P5             0x7777
#define HAM_CONTROL_WORD_P6             0xCCCC
#define HAM_BACKGROUND_RGB4             0x000

#define ROTO_START_X                    ((ROTO_SCREEN_WIDTH - ROTO_DISPLAY_WIDTH) / 2)
#define ROTO_DDF_SHIFT_BYTES            (ROTO_START_X >> 3)
#define ROTO_FETCH_BYTES                (ROTO_DISPLAY_WIDTH >> 3)
#define ROTO_PLANE_STRIDE               ROTO_FETCH_BYTES
#define ROTO_PLANE_BYTES                ((UWORD)(ROTO_PLANE_STRIDE * ROTO_DISPLAY_HEIGHT))
#define ROTO_SCREEN_BYTES               ((ULONG)ROTO_PLANE_BYTES * (ULONG)ROTO_DMA_BITPLANES)

#define ROTO_PAL_VPOS_TOP               0x2C
#define ROTO_VPOS_START                 (ROTO_PAL_VPOS_TOP + ((ROTO_SCREEN_HEIGHT - ROTO_DISPLAY_HEIGHT) / 2))
#define ROTO_VPOS_STOP                  (ROTO_VPOS_START + ROTO_DISPLAY_HEIGHT)
#define ROTO_DIWSTRT                    (UWORD)(((ROTO_VPOS_START & 0xFF) << 8) | 0x0081)
#define ROTO_DIWSTOP                    (UWORD)(((ROTO_VPOS_STOP  & 0xFF) << 8) | 0x00C1)
#define ROTO_DDFSTRT                    (0x0038 + (ROTO_DDF_SHIFT_BYTES * 4))
#define ROTO_DDFSTOP                    (0x00D0 - (ROTO_DDF_SHIFT_BYTES * 4))

#define SCREEN_COLORS                   32
#define ROTO_ZOOM_BASE                  384
#define ROTO_ZOOM_AMPLITUDE             128
#define ROTO_ZOOM_STEPS                 32
#define ROTO_ANGLE_PHASE_STEP           2
#define ROTO_DELTA_SCALE                3072
#define ROTO_CENTER_U                   0x4000
#define ROTO_CENTER_V                   0x4000

#define BUFFER_COUNT                    2

#define CUSTOM_BASE_ADDR               0xDFF000UL
#define DMACON_ADDR                    0x0096
#define DMAF_SETCLR_WORD               0x8000
#define DMAF_MASTER_WORD               0x0200
#define DMAF_BLITTER_WORD              0x0040
#define CUSTOM_UWORD(addr)             (*(volatile UWORD*)((CUSTOM_BASE_ADDR) + (addr)))

// Fixed HAM7 phase chosen from the previous phase-sweep test.
#define HAM_PHASE0_R_INDEX              0
#define HAM_PHASE0_G_INDEX              1
#define HAM_PHASE0_B_INDEX              2

#define BLIT_COMPARE_ROWS              ROTO_ROWS
#define BLIT_COMPARE_PLANE_BYTES       ((UWORD)(ROTO_FETCH_BYTES * BLIT_COMPARE_ROWS))
#define BLIT_COMPARE_SCREEN_BYTES      ((ULONG)BLIT_COMPARE_PLANE_BYTES * (ULONG)ROTO_DMA_BITPLANES)

typedef struct RotoRowStateTag
{
    WORD StartU;
    WORD StartV;
} RotoRowState;

typedef struct RotoFrameBlockTag
{
    WORD DuDx;
    WORD DvDx;
    RotoRowState Rows[ROTO_ROWS];
} RotoFrameBlock;

typedef struct RGBStateTag
{
    UBYTE R;
    UBYTE G;
    UBYTE B;
} RGBState;

typedef char RotoRowStateSizeMustBe4[(sizeof(RotoRowState) == 4) ? 1 : -1];
typedef char RotoFrameBlockSizeMustBe196[(sizeof(RotoFrameBlock) == 196) ? 1 : -1];

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

static const UBYTE ZeroPlaneRow[TEXTURE_SOURCE_WIDTH / 8] = { 0 };

static UWORD* TextureRGB4 = NULL;
static ULONG TextureRGB4Size = 0;
static UWORD DisplayPalette[SCREEN_COLORS];
static UBYTE* ScreenBuffers[BUFFER_COUNT] = { NULL, NULL };
static UBYTE* BlitPlanarBuffer = NULL;
static ULONG BlitPlanarBufferSize = 0;
static UBYTE* C2PTempBuffer = NULL;
static ULONG C2PTempBufferSize = 0;
static UWORD* CopperList = NULL;
static ULONG CopperListSize = 0;
static UWORD BPLPTH_Idx[ROTO_DMA_BITPLANES];
static UWORD BPLPTL_Idx[ROTO_DMA_BITPLANES];
static RotoFrameBlock* FrameBlocks = NULL;
static ULONG FrameBlocksSize = 0;
static RotoFrameBlock* CurrentFrameBlock = NULL;
static RotoFrameBlock* FrameBlocksEnd = NULL;

static UBYTE RGB4_R(UWORD RGB4) { return (UBYTE)((RGB4 >> 8) & 0x0FU); }
static UBYTE RGB4_G(UWORD RGB4) { return (UBYTE)((RGB4 >> 4) & 0x0FU); }
static UBYTE RGB4_B(UWORD RGB4) { return (UBYTE)(RGB4 & 0x0FU); }

static UBYTE ClampNibble(LONG Value)
{
    if (Value < 0)
    {
        return 0;
    }
    if (Value > 15)
    {
        return 15;
    }
    return (UBYTE)Value;
}

static UBYTE EncodeChannel(UBYTE Prev, UBYTE Target, UBYTE FirstIndex)
{
    const UBYTE AfterCount = (UBYTE)(4U - FirstIndex);
    const LONG Numerator = ((LONG)Target * 4L) - ((LONG)Prev * (LONG)FirstIndex);
    LONG Encoded;

    switch (AfterCount)
    {
        default:
        case 4:
            Encoded = (LONG)Target;
            break;

        case 3:
            Encoded = (Numerator >= 0) ? ((Numerator + 1L) / 3L) : (Numerator / 3L);
            break;

        case 2:
            Encoded = Numerator / 2L;
            break;

        case 1:
            Encoded = Numerator;
            break;
    }

    return ClampNibble(Encoded);
}

static void ClearPlaneRowBytes(UBYTE* P0, UBYTE* P1, UBYTE* P2, UBYTE* P3)
{
    UWORD i;
    for (i = 0; i < ROTO_FETCH_BYTES; ++i)
    {
        P0[i] = 0;
        P1[i] = 0;
        P2[i] = 0;
        P3[i] = 0;
    }
}

static void SetNibbleToPlaneBytes(UBYTE* P0, UBYTE* P1, UBYTE* P2, UBYTE* P3,
                                  UWORD X, UBYTE DataNibble)
{
    const UWORD ByteIndex = (UWORD)(X >> 3);
    const UBYTE Mask = (UBYTE)(1U << (7U - (X & 7U)));

    if (DataNibble & 0x01U) P0[ByteIndex] |= Mask;
    if (DataNibble & 0x02U) P1[ByteIndex] |= Mask;
    if (DataNibble & 0x04U) P2[ByteIndex] |= Mask;
    if (DataNibble & 0x08U) P3[ByteIndex] |= Mask;
}

static void WriteLogicalPixelPhase0(UBYTE* P0, UBYTE* P1, UBYTE* P2, UBYTE* P3,
                                    UWORD LogicalColumn, UWORD RGB4, RGBState* Prev)
{
    const UBYTE TargetR = RGB4_R(RGB4);
    const UBYTE TargetG = RGB4_G(RGB4);
    const UBYTE TargetB = RGB4_B(RGB4);
    const UBYTE EncR = EncodeChannel(Prev->R, TargetR, HAM_PHASE0_R_INDEX);
    const UBYTE EncG = EncodeChannel(Prev->G, TargetG, HAM_PHASE0_G_INDEX);
    const UBYTE EncB = EncodeChannel(Prev->B, TargetB, HAM_PHASE0_B_INDEX);
    const UWORD X = (UWORD)(LogicalColumn * 4U);

    SetNibbleToPlaneBytes(P0, P1, P2, P3, (UWORD)(X + 0U), EncR);
    SetNibbleToPlaneBytes(P0, P1, P2, P3, (UWORD)(X + 1U), EncG);
    SetNibbleToPlaneBytes(P0, P1, P2, P3, (UWORD)(X + 2U), EncB);
    SetNibbleToPlaneBytes(P0, P1, P2, P3, (UWORD)(X + 3U), EncB);

    Prev->R = EncR;
    Prev->G = EncG;
    Prev->B = EncB;
}

static const UWORD ScrambledRed[16] =
{
    0x0000,0x0008,0x0080,0x0088,0x0800,0x0808,0x0880,0x0888,
    0x8000,0x8008,0x8080,0x8088,0x8800,0x8808,0x8880,0x8888
};

static const UWORD ScrambledGreen[16] =
{
    0x0000,0x0004,0x0040,0x0044,0x0400,0x0404,0x0440,0x0444,
    0x4000,0x4004,0x4040,0x4044,0x4400,0x4404,0x4440,0x4444
};

static const UWORD ScrambledBlue[16] =
{
    0x0000,0x0003,0x0030,0x0033,0x0300,0x0303,0x0330,0x0333,
    0x3000,0x3003,0x3030,0x3033,0x3300,0x3303,0x3330,0x3333
};

static UWORD EncodeLogicalPixelPhase0Scrambled(UWORD RGB4, RGBState* Prev)
{
    const UBYTE TargetR = RGB4_R(RGB4);
    const UBYTE TargetG = RGB4_G(RGB4);
    const UBYTE TargetB = RGB4_B(RGB4);
    const UBYTE EncR = EncodeChannel(Prev->R, TargetR, HAM_PHASE0_R_INDEX);
    const UBYTE EncG = EncodeChannel(Prev->G, TargetG, HAM_PHASE0_G_INDEX);
    const UBYTE EncB = EncodeChannel(Prev->B, TargetB, HAM_PHASE0_B_INDEX);
    const UWORD Word = (UWORD)(ScrambledRed[EncR] | ScrambledGreen[EncG] | ScrambledBlue[EncB]);

    Prev->R = EncR;
    Prev->G = EncG;
    Prev->B = EncB;

    return Word;
}

static void CpuSwapScrambledRow(const UWORD* ScrambledRow, UWORD* TempRow)
{
    CpuSwapScrambledRowAsm(ScrambledRow, TempRow);
}

static void CopyPlaneRowToScreen(UBYTE* Screen,
                                 UWORD Y,
                                 const UBYTE* P0,
                                 const UBYTE* P1,
                                 const UBYTE* P2,
                                 const UBYTE* P3)
{
    const ULONG RowOffset = (ULONG)Y * (ULONG)ROTO_PLANE_STRIDE;
    UBYTE* Dst0 = Screen + ((ULONG)0 * (ULONG)ROTO_PLANE_BYTES) + RowOffset;
    UBYTE* Dst1 = Screen + ((ULONG)1 * (ULONG)ROTO_PLANE_BYTES) + RowOffset;
    UBYTE* Dst2 = Screen + ((ULONG)2 * (ULONG)ROTO_PLANE_BYTES) + RowOffset;
    UBYTE* Dst3 = Screen + ((ULONG)3 * (ULONG)ROTO_PLANE_BYTES) + RowOffset;
    UWORD i;

    for (i = 0; i < ROTO_FETCH_BYTES; ++i)
    {
        Dst0[i] = P0[i];
        Dst1[i] = P1[i];
        Dst2[i] = P2[i];
        Dst3[i] = P3[i];
    }
}

static void ClearByteBuffer(UBYTE* Buffer, ULONG Size)
{
    ULONG i;
    for (i = 0; i < Size; ++i)
    {
        Buffer[i] = 0;
    }
}

static void CopyPlanarBufferRowToScreen(UBYTE* Screen,
                                        UWORD DestY,
                                        const UBYTE* PlanarBuffer,
                                        UWORD SourceY)
{
    const ULONG SrcOffset = (ULONG)SourceY * (ULONG)ROTO_FETCH_BYTES;
    const ULONG DstOffset = (ULONG)DestY * (ULONG)ROTO_PLANE_STRIDE;
    const UBYTE* Src0 = PlanarBuffer + ((ULONG)0 * (ULONG)BLIT_COMPARE_PLANE_BYTES) + SrcOffset;
    const UBYTE* Src1 = PlanarBuffer + ((ULONG)1 * (ULONG)BLIT_COMPARE_PLANE_BYTES) + SrcOffset;
    const UBYTE* Src2 = PlanarBuffer + ((ULONG)2 * (ULONG)BLIT_COMPARE_PLANE_BYTES) + SrcOffset;
    const UBYTE* Src3 = PlanarBuffer + ((ULONG)3 * (ULONG)BLIT_COMPARE_PLANE_BYTES) + SrcOffset;
    UBYTE* Dst0 = Screen + ((ULONG)0 * (ULONG)ROTO_PLANE_BYTES) + DstOffset;
    UBYTE* Dst1 = Screen + ((ULONG)1 * (ULONG)ROTO_PLANE_BYTES) + DstOffset;
    UBYTE* Dst2 = Screen + ((ULONG)2 * (ULONG)ROTO_PLANE_BYTES) + DstOffset;
    UBYTE* Dst3 = Screen + ((ULONG)3 * (ULONG)ROTO_PLANE_BYTES) + DstOffset;
    UWORD i;

    for (i = 0; i < ROTO_FETCH_BYTES; ++i)
    {
        Dst0[i] = Src0[i];
        Dst1[i] = Src1[i];
        Dst2[i] = Src2[i];
        Dst3[i] = Src3[i];
    }
}

static void BuildDisplayPalette(const struct lwmf_Image* Image)
{
    UWORD i;
    const UWORD Limit = (Image->NumberOfColors < 16) ? Image->NumberOfColors : 16;

    for (i = 0; i < SCREEN_COLORS; ++i)
    {
        DisplayPalette[i] = 0x000;
    }

    DisplayPalette[0] = HAM_BACKGROUND_RGB4;

    for (i = 1; i < Limit; ++i)
    {
        DisplayPalette[i] = (UWORD)(Image->CRegs[i] & 0x0FFF);
    }
}

static void AllocTextureRGB4(void)
{
    TextureRGB4Size = TEXTURE_WORD_COUNT * (ULONG)sizeof(UWORD);
    TextureRGB4 = (UWORD*)lwmf_AllocCpuMem(TextureRGB4Size, MEMF_CLEAR);
}

static void BuildTextureFromHAM(const struct lwmf_Image* Image)
{
    UWORD BasePal[16] = { 0 };
    const UBYTE Depth = Image->Image.Depth;
    const UWORD ByteColumns = (TEXTURE_SOURCE_WIDTH / 8);
    const ULONG ImageRowBytes = (ULONG)Image->Image.BytesPerRow;
    const UWORD Limit = (Image->NumberOfColors < 16) ? Image->NumberOfColors : 16;
    UWORD i;
    UWORD Y;

    for (i = 0; i < Limit; ++i)
    {
        BasePal[i] = (UWORD)(Image->CRegs[i] & 0x0FFF);
    }

    for (Y = 0; Y < TEXTURE_SOURCE_HEIGHT; ++Y)
    {
        const ULONG PlaneRowOffset = (ULONG)Y * ImageRowBytes;
        const UBYTE* PlaneRows[8];
        UWORD CurrentRGB = BasePal[0];
        ULONG TexIndex = (ULONG)Y * (ULONG)TEXTURE_WIDTH;
        UWORD Plane;
        UWORD ByteX;

        for (Plane = 0; Plane < 8; ++Plane)
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

        for (ByteX = 0; ByteX < ByteColumns; ++ByteX)
        {
            UBYTE P0 = PlaneRows[0][ByteX];
            UBYTE P1 = PlaneRows[1][ByteX];
            UBYTE P2 = PlaneRows[2][ByteX];
            UBYTE P3 = PlaneRows[3][ByteX];
            UBYTE P4 = PlaneRows[4][ByteX];
            UBYTE P5 = PlaneRows[5][ByteX];
            UBYTE P6 = PlaneRows[6][ByteX];
            UBYTE P7 = PlaneRows[7][ByteX];
            UWORD Bit;

            for (Bit = 0; Bit < 8; ++Bit)
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
                const UBYTE Data = (UBYTE)(Pixel & 0x0FU);
                const UBYTE Ctrl = (UBYTE)(Pixel >> 4);
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
                        OutRGB = BasePal[Data & 0x0FU];
                        break;

                    case 1:
                        OutRGB = (UWORD)((CurrentRGB & 0x0FF0U) | Data);
                        break;

                    case 2:
                        OutRGB = (UWORD)((CurrentRGB & 0x00FFU) | ((UWORD)Data << 8));
                        break;

                    default:
                        OutRGB = (UWORD)((CurrentRGB & 0x0F0FU) | ((UWORD)Data << 4));
                        break;
                }

                CurrentRGB = OutRGB;
                TextureRGB4[TexIndex++] = OutRGB;
            }
        }
    }
}

static void InitTexture(void)
{
    struct lwmf_Image* Image = lwmf_LoadImage(TEXTURE_FILENAME);
    BuildDisplayPalette(Image);
    AllocTextureRGB4();
    BuildTextureFromHAM(Image);
    lwmf_DeleteImage(Image);
}

static void BuildFrameStates(void)
{
    UWORD Frame;

    FrameBlocksSize = 256UL * (ULONG)sizeof(RotoFrameBlock);
    FrameBlocks = (RotoFrameBlock*)lwmf_AllocCpuMem(FrameBlocksSize, MEMF_CLEAR);

    for (Frame = 0; Frame < 256U; ++Frame)
    {
        const UBYTE AnglePhase = (UBYTE)(Frame * ROTO_ANGLE_PHASE_STEP);
        const UBYTE ZoomPhase = (UBYTE)Frame;
        const UBYTE MovePhaseX = (UBYTE)Frame;
        const UBYTE MovePhaseY = (UBYTE)(64U + (Frame * 2U));
        const LONG ZoomIndex = (LONG)(((ULONG)SinTab256[ZoomPhase] * 31UL) / 63UL);
        const LONG Zoom =
            (LONG)ROTO_ZOOM_BASE -
            (LONG)ROTO_ZOOM_AMPLITUDE +
            ((ZoomIndex * ((LONG)ROTO_ZOOM_AMPLITUDE * 2L)) / (LONG)(ROTO_ZOOM_STEPS - 1));
        const LONG SinV = (LONG)((WORD)SinTab256[AnglePhase] - 32);
        const LONG CosV = (LONG)((WORD)SinTab256[(UBYTE)(AnglePhase + 64U)] - 32);
        const WORD DuDx = (WORD)((CosV * ROTO_DELTA_SCALE) / Zoom);
        const WORD DvDx = (WORD)((SinV * ROTO_DELTA_SCALE) / Zoom);
        const LONG StartUOffset =
            -((LONG)ROTO_HALF_COLUMNS * (LONG)DuDx) +
             ((LONG)ROTO_HALF_ROWS    * (LONG)DvDx);
        const LONG StartVOffset =
            -((LONG)ROTO_HALF_COLUMNS * (LONG)DvDx) -
             ((LONG)ROTO_HALF_ROWS    * (LONG)DuDx);
        const WORD MoveX = (WORD)(((WORD)SinTab256[MovePhaseX] - 32) << 8);
        const WORD MoveY = (WORD)(((WORD)SinTab256[MovePhaseY] - 32) << 8);
        const WORD StartU = (WORD)((WORD)ROTO_CENTER_U + MoveX + (WORD)StartUOffset);
        const WORD StartV = (WORD)((WORD)ROTO_CENTER_V + MoveY + (WORD)StartVOffset);
        RotoFrameBlock* Block = &FrameBlocks[Frame];
        UWORD Row;

        Block->DuDx = DuDx;
        Block->DvDx = DvDx;

        for (Row = 0; Row < ROTO_ROWS; ++Row)
        {
            Block->Rows[Row].StartU = (WORD)(StartU + (WORD)((LONG)Row * (LONG)DvDx));
            Block->Rows[Row].StartV = (WORD)(StartV - (WORD)((LONG)Row * (LONG)DuDx));
        }
    }
}

static void InitScreenBuffers(void)
{
    UWORD i;
    for (i = 0; i < BUFFER_COUNT; ++i)
    {
        ScreenBuffers[i] = (UBYTE*)AllocMem(ROTO_SCREEN_BYTES, MEMF_CHIP | MEMF_CLEAR);
    }

    BlitPlanarBufferSize = BLIT_COMPARE_SCREEN_BYTES;
    BlitPlanarBuffer = (UBYTE*)AllocMem(BlitPlanarBufferSize, MEMF_CHIP | MEMF_CLEAR);

    C2PTempBufferSize = BLIT_COMPARE_SCREEN_BYTES;
    C2PTempBuffer = (UBYTE*)AllocMem(C2PTempBufferSize, MEMF_CHIP | MEMF_CLEAR);
}

static void ClearWholeScreen(UBYTE* Screen)
{
    ULONG i;
    for (i = 0; i < ROTO_SCREEN_BYTES; ++i)
    {
        Screen[i] = 0;
    }
}

static void RenderHam7Frame(const RotoFrameBlock* Frame, UBYTE* Screen)
{
    UWORD LogicalRow;
    UWORD Rep;

    /* Screen, Temp and Planar buffers are fully overwritten each frame. */

    for (LogicalRow = 0; LogicalRow < ROTO_ROWS; ++LogicalRow)
    {
        WORD U = Frame->Rows[LogicalRow].StartU;
        WORD V = Frame->Rows[LogicalRow].StartV;
        RGBState Prev;
        UWORD LogicalColumn;
        UWORD ScrambledRow[ROTO_COLUMNS];
        UWORD* TempRow = (UWORD*)C2PTempBuffer + ((ULONG)LogicalRow * (ULONG)ROTO_COLUMNS);

        Prev.R = (UBYTE)((HAM_BACKGROUND_RGB4 >> 8) & 0x0FU);
        Prev.G = (UBYTE)((HAM_BACKGROUND_RGB4 >> 4) & 0x0FU);
        Prev.B = (UBYTE)(HAM_BACKGROUND_RGB4 & 0x0FU);

        for (LogicalColumn = 0; LogicalColumn < ROTO_COLUMNS; ++LogicalColumn)
        {
            const UBYTE Uc = (UBYTE)(((UWORD)U) >> 8);
            const UBYTE Vc = (UBYTE)(((UWORD)V) >> 8);
            const UWORD RGB4 = TextureRGB4[((UWORD)(Vc & 0x7FU) << 7) | (UWORD)(Uc & 0x7FU)];

            ScrambledRow[LogicalColumn] = EncodeLogicalPixelPhase0Scrambled(RGB4, &Prev);

            U = (WORD)(U + Frame->DuDx);
            V = (WORD)(V + Frame->DvDx);
        }

        CpuSwapScrambledRow(ScrambledRow, TempRow);
    }

    RunC2PExtractAsm((const UWORD*)C2PTempBuffer, BlitPlanarBuffer);

    for (LogicalRow = 0; LogicalRow < ROTO_ROWS; ++LogicalRow)
    {
        for (Rep = 0; Rep < ROTO_PIXEL_SCALE; ++Rep)
        {
            CopyPlanarBufferRowToScreen(Screen,
                                        (UWORD)(LogicalRow * ROTO_PIXEL_SCALE + Rep),
                                        BlitPlanarBuffer,
                                        LogicalRow);
        }
    }
}

static void Init_CopperList(void)
{
    const ULONG CopperWords = 24 + (4 * ROTO_DMA_BITPLANES) + (SCREEN_COLORS * 2) + 2;
    UWORD Index = 0;
    UWORD Plane;
    UWORD c;

    CopperListSize = CopperWords * sizeof(UWORD);
    CopperList = (UWORD*)AllocMem(CopperListSize, MEMF_CHIP | MEMF_CLEAR);

    CopperList[Index++] = 0x008E; CopperList[Index++] = ROTO_DIWSTRT;
    CopperList[Index++] = 0x0090; CopperList[Index++] = ROTO_DIWSTOP;
    CopperList[Index++] = 0x0092; CopperList[Index++] = ROTO_DDFSTRT;
    CopperList[Index++] = 0x0094; CopperList[Index++] = ROTO_DDFSTOP;

    CopperList[Index++] = 0x0100; CopperList[Index++] = HAM_BPLCON0;
    CopperList[Index++] = 0x0102; CopperList[Index++] = 0x0000;
    CopperList[Index++] = 0x0104; CopperList[Index++] = 0x0000;
    CopperList[Index++] = 0x0108; CopperList[Index++] = 0x0000;
    CopperList[Index++] = 0x010A; CopperList[Index++] = 0x0000;

    CopperList[Index++] = 0x0118; CopperList[Index++] = HAM_CONTROL_WORD_P5;
    CopperList[Index++] = 0x011A; CopperList[Index++] = HAM_CONTROL_WORD_P6;

    for (Plane = 0; Plane < ROTO_DMA_BITPLANES; ++Plane)
    {
        CopperList[Index++] = (UWORD)(0x00E0 + (Plane * 4));
        BPLPTH_Idx[Plane] = Index;
        CopperList[Index++] = 0x0000;

        CopperList[Index++] = (UWORD)(0x00E2 + (Plane * 4));
        BPLPTL_Idx[Plane] = Index;
        CopperList[Index++] = 0x0000;
    }

    for (c = 0; c < SCREEN_COLORS; ++c)
    {
        CopperList[Index++] = (UWORD)(0x0180 + (c * 2));
        CopperList[Index++] = DisplayPalette[c];
    }

    CopperList[Index++] = 0xFFFF;
    CopperList[Index++] = 0xFFFE;

    *COP1LC = (ULONG)CopperList;
}

static void Update_BitplanePointers(UWORD BufferIndex)
{
    ULONG Ptr = (ULONG)ScreenBuffers[BufferIndex];
    UWORD Plane;

    for (Plane = 0; Plane < ROTO_DMA_BITPLANES; ++Plane)
    {
        CopperList[BPLPTH_Idx[Plane]] = (UWORD)(Ptr >> 16);
        CopperList[BPLPTL_Idx[Plane]] = (UWORD)(Ptr & 0xFFFF);
        Ptr += ROTO_PLANE_BYTES;
    }
}

static void Cleanup_All(void)
{
    UWORD i;

    if (BlitPlanarBuffer != NULL)
    {
        FreeMem(BlitPlanarBuffer, BlitPlanarBufferSize);
        BlitPlanarBuffer = NULL;
        BlitPlanarBufferSize = 0;
    }

    if (C2PTempBuffer != NULL)
    {
        FreeMem(C2PTempBuffer, C2PTempBufferSize);
        C2PTempBuffer = NULL;
        C2PTempBufferSize = 0;
    }

    if (CopperList != NULL)
    {
        FreeMem(CopperList, CopperListSize);
        CopperList = NULL;
        CopperListSize = 0;
    }

    if (TextureRGB4 != NULL)
    {
        FreeMem(TextureRGB4, TextureRGB4Size);
        TextureRGB4 = NULL;
        TextureRGB4Size = 0;
    }

    if (FrameBlocks != NULL)
    {
        FreeMem(FrameBlocks, FrameBlocksSize);
        FrameBlocks = NULL;
        FrameBlocksSize = 0;
        CurrentFrameBlock = NULL;
        FrameBlocksEnd = NULL;
    }

    for (i = 0; i < BUFFER_COUNT; ++i)
    {
        if (ScreenBuffers[i] != NULL)
        {
            FreeMem(ScreenBuffers[i], ROTO_SCREEN_BYTES);
            ScreenBuffers[i] = NULL;
        }
    }

    lwmf_CleanupAll();
}

int main(void)
{
    UWORD DrawBuffer = 1;

    lwmf_LoadGraphicsLib();
    InitTexture();
    BuildFrameStates();
    FrameBlocksEnd = FrameBlocks + 256;
    CurrentFrameBlock = &FrameBlocks[0];
    InitScreenBuffers();
    Init_CopperList();

    RenderHam7Frame(CurrentFrameBlock, ScreenBuffers[0]);
    Update_BitplanePointers(0);
    lwmf_TakeOverOS();
    CUSTOM_UWORD(DMACON_ADDR) = (UWORD)(DMAF_SETCLR_WORD | DMAF_MASTER_WORD | DMAF_BLITTER_WORD);

    while (*CIAA_PRA & 0x40)
    {
        ++CurrentFrameBlock;
        if (CurrentFrameBlock == FrameBlocksEnd)
        {
            CurrentFrameBlock = FrameBlocks;
        }

        DBG_COLOR(0x00F);
        RenderHam7Frame(CurrentFrameBlock, ScreenBuffers[DrawBuffer]);
        DBG_COLOR(0x000);

        lwmf_WaitVertBlank();
        Update_BitplanePointers(DrawBuffer);
        DrawBuffer ^= 1;
    }

    Cleanup_All();
    return 0;
}
