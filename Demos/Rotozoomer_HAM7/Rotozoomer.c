//**********************************************************************
//* 4x4 HAM7 Rotozoomer                                                *
//*                                                                    *
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

struct RotoFrameChunkTag;

extern void RunC2PExtractAsm(__reg("a0") const UWORD* Temp, __reg("a1") UBYTE* Planar);
extern void StartC2PPlane3Asm(__reg("a0") const UWORD* Temp, __reg("a1") UBYTE* Planar);
extern void StartC2PPlane1Asm(__reg("a0") const UWORD* Temp, __reg("a1") UBYTE* Planar);
extern void StartC2PPlane2Asm(__reg("a0") const UWORD* Temp, __reg("a1") UBYTE* Planar);
extern void StartC2PPlane0Asm(__reg("a0") const UWORD* Temp, __reg("a1") UBYTE* Planar);
extern void RenderPhase0TempRowsChunkAsm(__reg("a0") const struct RotoFrameChunkTag* Frame, __reg("a1") const UWORD* TextureRGBase, __reg("a2") UWORD* TempFrame);

#define DEBUG 0
#if DEBUG
#define DBG_COLOR(c) (*COLOR00 = (c))
#else
#define DBG_COLOR(c) ((void)0)
#endif

#define DBG_COLOR_IDLE                 0x000
#define DBG_COLOR_RENDER               0xF00
#define DBG_COLOR_C2P                  0x0F0

#define TEXTURE_FILENAME                "gfx/128x128_ham.iff"
#define TEXTURE_SOURCE_WIDTH            128
#define TEXTURE_SOURCE_HEIGHT           128
#define TEXTURE_WIDTH                   TEXTURE_SOURCE_WIDTH
#define TEXTURE_HEIGHT                  TEXTURE_SOURCE_HEIGHT
#define TEXTURE_WORD_COUNT              ((ULONG)TEXTURE_WIDTH * (ULONG)TEXTURE_HEIGHT)

#define ROTO_COLUMNS                    28
#define ROTO_ROWS                       48
#define ROTO_CHUNK_ROWS                 16
#define ROTO_CHUNK_COUNT                (ROTO_ROWS / ROTO_CHUNK_ROWS)
#define ROTO_PIXEL_SCALE                4
#define ROTO_DISPLAY_WIDTH              (ROTO_COLUMNS * ROTO_PIXEL_SCALE)
#define ROTO_DISPLAY_HEIGHT             (ROTO_ROWS * ROTO_PIXEL_SCALE)
#define ROTO_HALF_COLUMNS               (ROTO_COLUMNS / 2)
#define ROTO_HALF_ROWS                  (ROTO_ROWS / 2)

#define ROTO_SCREEN_WIDTH               320
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
#define ROTO_PLANE_BYTES                ((UWORD)(ROTO_PLANE_STRIDE * ROTO_ROWS))
#define ROTO_SCREEN_BYTES               ((ULONG)ROTO_PLANE_BYTES * (ULONG)ROTO_DMA_BITPLANES)
#define ROTO_CHUNK_BYTES                ((ULONG)ROTO_FETCH_BYTES * (ULONG)ROTO_CHUNK_ROWS * (ULONG)ROTO_DMA_BITPLANES)
#define ROTO_REPEAT_MODULO              ((UWORD)(0U - (UWORD)ROTO_FETCH_BYTES))

/* Slight upward shift so all modulo-repeat copper waits stay within OCS 8-bit VPOS. */
#define ROTO_VPOS_START                 63
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
#define DMAF_BLITPRI_WORD              0x0400
#define DMAF_BLITTER_WORD              0x0040
#define CUSTOM_UWORD(addr)             (*(volatile UWORD*)((CUSTOM_BASE_ADDR) + (addr)))

typedef struct RotoRowStateTag
{
    WORD StartU;
    WORD StartV;
} RotoRowState;

typedef struct RotoFrameChunkTag
{
    WORD DuDx;
    WORD DvDx;
    RotoRowState Rows[ROTO_CHUNK_ROWS];
} RotoFrameChunk;

typedef char RotoRowStateSizeMustBe4[(sizeof(RotoRowState) == 4) ? 1 : -1];
typedef char RotoFrameChunkSizeMustBe68[(sizeof(RotoFrameChunk) == 68) ? 1 : -1];

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

static UWORD* TextureRGBase = NULL;
static ULONG TextureRGBaseSize = 0;
UWORD* TextureBlueWord = NULL;
static ULONG TextureBlueWordSize = 0;
static UWORD DisplayPalette[SCREEN_COLORS];
static UBYTE* ScreenBuffers[BUFFER_COUNT] = { NULL, NULL };
static UBYTE* C2PTempBuffers[BUFFER_COUNT] = { NULL, NULL };
static ULONG C2PTempBufferSize = 0;
static UWORD* CopperList = NULL;
static ULONG CopperListSize = 0;
static UWORD BPLPTH_Idx[ROTO_DMA_BITPLANES];
static UWORD BPLPTL_Idx[ROTO_DMA_BITPLANES];
static RotoFrameChunk* FrameChunks = NULL;
static ULONG FrameChunksSize = 0;
static RotoFrameChunk* CurrentFrameChunks = NULL;
static RotoFrameChunk* FrameChunksEnd = NULL;

static const UWORD Ham7Phase0RedWord[16] =
{
    0x0000,0x0008,0x0080,0x0088,0x0800,0x0808,0x0880,0x0888,
    0x8000,0x8008,0x8080,0x8088,0x8800,0x8808,0x8880,0x8888
};

static const UWORD Ham7Phase0GreenWord[16] =
{
    0x0000,0x0004,0x0040,0x0044,0x0400,0x0404,0x0440,0x0444,
    0x4000,0x4004,0x4040,0x4044,0x4400,0x4404,0x4440,0x4444
};

static const UWORD Ham7Phase0BlueWord[16] =
{
    0x0000,0x0003,0x0030,0x0033,0x0300,0x0303,0x0330,0x0333,
    0x3000,0x3003,0x3030,0x3033,0x3300,0x3303,0x3330,0x3333
};

#define HAM7_PHASE0_RG_PACK_ENTRIES    4096UL

ULONG* Ham7Phase0RGPack = NULL;
static ULONG Ham7Phase0RGPackSize = 0;

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

static UBYTE EncodeGreenPhase0Nibble(UBYTE PrevG, UBYTE TargetG)
{
    const LONG Numerator = ((LONG)TargetG * 4L) - (LONG)PrevG;
    const LONG Encoded = (Numerator >= 0L) ? ((Numerator + 1L) / 3L) : (Numerator / 3L);
    return ClampNibble(Encoded);
}

static UBYTE EncodeBluePhase0Nibble(UBYTE PrevB, UBYTE TargetB)
{
    (void)PrevB;
    return TargetB;
}

static void AllocPhase0PackedTables(void)
{
    Ham7Phase0RGPackSize = HAM7_PHASE0_RG_PACK_ENTRIES * (ULONG)sizeof(ULONG);
    Ham7Phase0RGPack = (ULONG*)lwmf_AllocCpuMem(Ham7Phase0RGPackSize, MEMF_CLEAR);
}

static void BuildPhase0PackedTables(void)
{
    for (UWORD Prev = 0; Prev < 16U; ++Prev)
    {
        for (UWORD RG = 0; RG < 256U; ++RG)
        {
            const UBYTE TargetR = (UBYTE)(RG >> 4);
            const UBYTE TargetG = (UBYTE)(RG & 0x0FU);
            const UBYTE EncodedGreen = EncodeGreenPhase0Nibble((UBYTE)Prev, TargetG);
            const UWORD Word = (UWORD)(Ham7Phase0RedWord[TargetR] | Ham7Phase0GreenWord[EncodedGreen]);

            Ham7Phase0RGPack[((UWORD)Prev << 8) | RG] = (((ULONG)Word) << 16) | ((ULONG)EncodedGreen << 10);
        }
    }
}

static void BuildDisplayPalette(const struct lwmf_Image* Image)
{
    const UWORD Limit = (Image->NumberOfColors < 16) ? Image->NumberOfColors : 16;

    for (UWORD i = 0; i < SCREEN_COLORS; ++i)
    {
        DisplayPalette[i] = 0x000;
    }

    DisplayPalette[0] = HAM_BACKGROUND_RGB4;

    for (UWORD i = 1; i < Limit; ++i)
    {
        DisplayPalette[i] = (UWORD)(Image->CRegs[i] & 0x0FFF);
    }
}

static void AllocTextureTables(void)
{
    TextureRGBaseSize = TEXTURE_WORD_COUNT * (ULONG)sizeof(UWORD);
    TextureBlueWordSize = TEXTURE_WORD_COUNT * (ULONG)sizeof(UWORD);
    TextureRGBase = (UWORD*)lwmf_AllocCpuMem(TextureRGBaseSize, MEMF_CLEAR);
    TextureBlueWord = (UWORD*)lwmf_AllocCpuMem(TextureBlueWordSize, MEMF_CLEAR);
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

    for (UWORD y = 0; y < TEXTURE_SOURCE_HEIGHT; ++y)
    {
        const ULONG PlaneRowOffset = (ULONG)y * ImageRowBytes;
        const UBYTE* PlaneRows[8];
        UWORD CurrentRGB = BasePal[0];
        ULONG TexIndex = (ULONG)y * (ULONG)TEXTURE_WIDTH;

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
                TextureRGBase[TexIndex] = (UWORD)(((OutRGB >> 4) & 0x00FFU) << 2);
                TextureBlueWord[TexIndex] = Ham7Phase0BlueWord[EncodeBluePhase0Nibble(0U, (UBYTE)(OutRGB & 0x0FU))];
                ++TexIndex;
            }
        }
    }
}

static void InitTexture(void)
{
    struct lwmf_Image* Image = lwmf_LoadImage(TEXTURE_FILENAME);
    BuildDisplayPalette(Image);
    AllocTextureTables();
    BuildTextureFromHAM(Image);
    lwmf_DeleteImage(Image);
}

static void BuildFrameStates(void)
{
    FrameChunksSize = (256UL * (ULONG)ROTO_CHUNK_COUNT) * (ULONG)sizeof(RotoFrameChunk);
    FrameChunks = (RotoFrameChunk*)lwmf_AllocCpuMem(FrameChunksSize, MEMF_CLEAR);

    for (UWORD Frame = 0; Frame < 256U; ++Frame)
    {
        const UBYTE AnglePhase = (UBYTE)(Frame * ROTO_ANGLE_PHASE_STEP);
        const UBYTE ZoomPhase = (UBYTE)Frame;
        const UBYTE MovePhaseX = (UBYTE)Frame;
        const UBYTE MovePhaseY = (UBYTE)(64U + (Frame * 2U));
        const LONG ZoomIndex = (LONG)(((ULONG)SinTab256[ZoomPhase] * 31UL) / 63UL);
        const LONG Zoom = (LONG)ROTO_ZOOM_BASE - (LONG)ROTO_ZOOM_AMPLITUDE + ((ZoomIndex * ((LONG)ROTO_ZOOM_AMPLITUDE * 2L)) / (LONG)(ROTO_ZOOM_STEPS - 1));
        const LONG SinV = (LONG)((WORD)SinTab256[AnglePhase] - 32);
        const LONG CosV = (LONG)((WORD)SinTab256[(UBYTE)(AnglePhase + 64U)] - 32);
        const WORD DuDx = (WORD)((CosV * ROTO_DELTA_SCALE) / Zoom);
        const WORD DvDx = (WORD)((SinV * ROTO_DELTA_SCALE) / Zoom);
        const LONG StartUOffset = -((LONG)ROTO_HALF_COLUMNS * (LONG)DuDx) + ((LONG)ROTO_HALF_ROWS * (LONG)DvDx);
        const LONG StartVOffset = -((LONG)ROTO_HALF_COLUMNS * (LONG)DvDx) - ((LONG)ROTO_HALF_ROWS * (LONG)DuDx);
        const WORD MoveX = (WORD)(((WORD)SinTab256[MovePhaseX] - 32) << 8);
        const WORD MoveY = (WORD)(((WORD)SinTab256[MovePhaseY] - 32) << 8);
        WORD RowU = (WORD)((WORD)ROTO_CENTER_U + MoveX + (WORD)StartUOffset);
        WORD RowV = (WORD)((WORD)ROTO_CENTER_V + MoveY + (WORD)StartVOffset);
        RotoFrameChunk* Chunks = &FrameChunks[(ULONG)Frame * (ULONG)ROTO_CHUNK_COUNT];

        for (UWORD Chunk = 0; Chunk < ROTO_CHUNK_COUNT; ++Chunk)
        {
            Chunks[Chunk].DuDx = DuDx;
            Chunks[Chunk].DvDx = DvDx;

            for (UWORD Row = 0; Row < ROTO_CHUNK_ROWS; ++Row)
            {
                Chunks[Chunk].Rows[Row].StartU = RowU;
                Chunks[Chunk].Rows[Row].StartV = RowV;
                RowU = (WORD)(RowU + DvDx);
                RowV = (WORD)(RowV - DuDx);
            }
        }
    }
}

static void InitScreenBuffers(void)
{
    for (UWORD i = 0; i < BUFFER_COUNT; ++i)
    {
        ScreenBuffers[i] = (UBYTE*)AllocMem(ROTO_SCREEN_BYTES, MEMF_CHIP | MEMF_CLEAR);
    }

    C2PTempBufferSize = ROTO_SCREEN_BYTES;

    for (UWORD i = 0; i < BUFFER_COUNT; ++i)
    {
        C2PTempBuffers[i] = (UBYTE*)AllocMem(C2PTempBufferSize, MEMF_CHIP | MEMF_CLEAR);
    }
}

static void AdvanceCurrentFrameChunks(void)
{
    CurrentFrameChunks += ROTO_CHUNK_COUNT;

    if (CurrentFrameChunks == FrameChunksEnd)
    {
        CurrentFrameChunks = FrameChunks;
    }
}

static void EnableBlitterPriority(void)
{
    CUSTOM_UWORD(DMACON_ADDR) = (UWORD)(DMAF_SETCLR_WORD | DMAF_BLITPRI_WORD);
}

static void DisableBlitterPriority(void)
{
    CUSTOM_UWORD(DMACON_ADDR) = DMAF_BLITPRI_WORD;
}

static void RenderTempChunk(const RotoFrameChunk* Chunk, UBYTE* TempBuffer)
{
    RenderPhase0TempRowsChunkAsm(Chunk, TextureRGBase, (UWORD*)TempBuffer);
}

static void RenderTempFrame(const RotoFrameChunk* Chunks, UBYTE* TempBuffer)
{
    RenderTempChunk(&Chunks[0], TempBuffer + (0UL * ROTO_CHUNK_BYTES));
    RenderTempChunk(&Chunks[1], TempBuffer + (1UL * ROTO_CHUNK_BYTES));
    RenderTempChunk(&Chunks[2], TempBuffer + (2UL * ROTO_CHUNK_BYTES));
}

static void BlitFrameSync(const UBYTE* TempBuffer, UBYTE* Screen)
{
    EnableBlitterPriority();
    RunC2PExtractAsm((const UWORD*)TempBuffer, Screen);
    DisableBlitterPriority();
}


static UWORD DisplayLineModulo(UWORD DisplayY)
{
    return ((DisplayY & (ROTO_PIXEL_SCALE - 1U)) == (ROTO_PIXEL_SCALE - 1U)) ? 0x0000U : ROTO_REPEAT_MODULO;
}

static void Init_CopperList(void)
{
    const ULONG CopperWords = 24UL + (ULONG)(4 * ROTO_DMA_BITPLANES) + (ULONG)(SCREEN_COLORS * 2) + ((ULONG)(ROTO_DISPLAY_HEIGHT - 1U) * 6UL) + 2UL;

    CopperListSize = CopperWords * sizeof(UWORD);
    CopperList = (UWORD*)AllocMem(CopperListSize, MEMF_CHIP | MEMF_CLEAR);

    UWORD Index = 0;

    CopperList[Index++] = 0x008E; CopperList[Index++] = ROTO_DIWSTRT;
    CopperList[Index++] = 0x0090; CopperList[Index++] = ROTO_DIWSTOP;
    CopperList[Index++] = 0x0092; CopperList[Index++] = ROTO_DDFSTRT;
    CopperList[Index++] = 0x0094; CopperList[Index++] = ROTO_DDFSTOP;

    CopperList[Index++] = 0x0100; CopperList[Index++] = HAM_BPLCON0;
    CopperList[Index++] = 0x0102; CopperList[Index++] = 0x0000;
    CopperList[Index++] = 0x0104; CopperList[Index++] = 0x0000;
    CopperList[Index++] = 0x0108; CopperList[Index++] = DisplayLineModulo(0);
    CopperList[Index++] = 0x010A; CopperList[Index++] = DisplayLineModulo(0);

    CopperList[Index++] = 0x0118; CopperList[Index++] = HAM_CONTROL_WORD_P5;
    CopperList[Index++] = 0x011A; CopperList[Index++] = HAM_CONTROL_WORD_P6;

    for (UWORD Plane = 0; Plane < ROTO_DMA_BITPLANES; ++Plane)
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

    for (UWORD DisplayY = 1; DisplayY < ROTO_DISPLAY_HEIGHT; ++DisplayY)
    {
        const UWORD WaitVPos = (UWORD)(ROTO_VPOS_START + DisplayY);
        CopperList[Index++] = (UWORD)(((WaitVPos & 0x00FFU) << 8) | 0x0007U);
        CopperList[Index++] = 0xFFFE;
        CopperList[Index++] = 0x0108; CopperList[Index++] = DisplayLineModulo(DisplayY);
        CopperList[Index++] = 0x010A; CopperList[Index++] = DisplayLineModulo(DisplayY);
    }

    CopperList[Index++] = 0xFFFF;
    CopperList[Index++] = 0xFFFE;

    *COP1LC = (ULONG)CopperList;
}

static void Update_BitplanePointers(UWORD BufferIndex)
{
    ULONG Ptr = (ULONG)ScreenBuffers[BufferIndex];

    for (UWORD Plane = 0; Plane < ROTO_DMA_BITPLANES; ++Plane)
    {
        CopperList[BPLPTH_Idx[Plane]] = (UWORD)(Ptr >> 16);
        CopperList[BPLPTL_Idx[Plane]] = (UWORD)(Ptr & 0xFFFF);
        Ptr += ROTO_PLANE_BYTES;
    }
}

static void Cleanup_All(void)
{
    for (UWORD i = 0; i < BUFFER_COUNT; ++i)
    {
        FreeMem(C2PTempBuffers[i], C2PTempBufferSize);
        C2PTempBuffers[i] = NULL;
    }

    C2PTempBufferSize = 0;
    FreeMem(CopperList, CopperListSize);
    CopperList = NULL;
    CopperListSize = 0;
    FreeMem(TextureRGBase, TextureRGBaseSize);
    TextureRGBase = NULL;
    TextureRGBaseSize = 0;
    FreeMem(TextureBlueWord, TextureBlueWordSize);
    TextureBlueWord = NULL;
    TextureBlueWordSize = 0;
    FreeMem(Ham7Phase0RGPack, Ham7Phase0RGPackSize);
    Ham7Phase0RGPack = NULL;
    Ham7Phase0RGPackSize = 0;
    FreeMem(FrameChunks, FrameChunksSize);
    FrameChunks = NULL;
    FrameChunksSize = 0;
    CurrentFrameChunks = NULL;
    FrameChunksEnd = NULL;

    for (UWORD i = 0; i < BUFFER_COUNT; ++i)
    {
        FreeMem(ScreenBuffers[i], ROTO_SCREEN_BYTES);
        ScreenBuffers[i] = NULL;
    }

    lwmf_CleanupAll();
}

int main(void)
{
    lwmf_LoadGraphicsLib();

    InitTexture();
    AllocPhase0PackedTables();
    BuildPhase0PackedTables();
    BuildFrameStates();
    FrameChunksEnd = FrameChunks + (256 * ROTO_CHUNK_COUNT);
    CurrentFrameChunks = &FrameChunks[0];

    InitScreenBuffers();
    Init_CopperList();

    DBG_COLOR(DBG_COLOR_RENDER);
    RenderTempFrame(CurrentFrameChunks, C2PTempBuffers[0]);
    DBG_COLOR(DBG_COLOR_C2P);
    BlitFrameSync(C2PTempBuffers[0], ScreenBuffers[0]);
    DBG_COLOR(DBG_COLOR_IDLE);
    Update_BitplanePointers(0);
    AdvanceCurrentFrameChunks();

    DBG_COLOR(DBG_COLOR_RENDER);
    RenderTempFrame(CurrentFrameChunks, C2PTempBuffers[1]);
    DBG_COLOR(DBG_COLOR_IDLE);
    AdvanceCurrentFrameChunks();

    lwmf_TakeOverOS();
    CUSTOM_UWORD(DMACON_ADDR) = (UWORD)(DMAF_SETCLR_WORD | DMAF_MASTER_WORD | DMAF_BLITTER_WORD);

    UWORD DrawBuffer = 1;
    UWORD ReadyTemp = 1;
    UWORD RenderTemp = 0;

    while (*CIAA_PRA & 0x40)
    {
        DBG_COLOR(DBG_COLOR_C2P);
        StartC2PPlane3Asm((const UWORD*)C2PTempBuffers[ReadyTemp], ScreenBuffers[DrawBuffer]);

        DBG_COLOR(DBG_COLOR_RENDER);
        RenderTempChunk(&CurrentFrameChunks[0], C2PTempBuffers[RenderTemp] + (0UL * ROTO_CHUNK_BYTES));

        DBG_COLOR(DBG_COLOR_C2P);
        lwmf_WaitBlitter();
        StartC2PPlane1Asm((const UWORD*)C2PTempBuffers[ReadyTemp], ScreenBuffers[DrawBuffer]);

        DBG_COLOR(DBG_COLOR_RENDER);
        RenderTempChunk(&CurrentFrameChunks[1], C2PTempBuffers[RenderTemp] + (1UL * ROTO_CHUNK_BYTES));

        DBG_COLOR(DBG_COLOR_C2P);
        lwmf_WaitBlitter();
        StartC2PPlane2Asm((const UWORD*)C2PTempBuffers[ReadyTemp], ScreenBuffers[DrawBuffer]);

        DBG_COLOR(DBG_COLOR_RENDER);
        RenderTempChunk(&CurrentFrameChunks[2], C2PTempBuffers[RenderTemp] + (2UL * ROTO_CHUNK_BYTES));
        AdvanceCurrentFrameChunks();

        DBG_COLOR(DBG_COLOR_C2P);
        lwmf_WaitBlitter();
        EnableBlitterPriority();
        StartC2PPlane0Asm((const UWORD*)C2PTempBuffers[ReadyTemp], ScreenBuffers[DrawBuffer]);
        lwmf_WaitVertBlank();
        lwmf_WaitBlitter();
        DisableBlitterPriority();
        DBG_COLOR(DBG_COLOR_IDLE);

        Update_BitplanePointers(DrawBuffer);
        DrawBuffer ^= 1;

        {
            const UWORD TempSwap = ReadyTemp;
            ReadyTemp = RenderTemp;
            RenderTemp = TempSwap;
        }
    }

    Cleanup_All();
    return 0;
}
