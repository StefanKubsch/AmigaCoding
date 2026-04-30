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

struct RotoFrameStateTag;

extern void RunC2PExtractAsm(__reg("a0") const UWORD* Temp, __reg("a1") UBYTE* Planar);
extern void StartC2PPlane3Asm(__reg("a0") const UWORD* Temp, __reg("a1") UBYTE* Planar);
extern void StartC2PPlane1Asm(__reg("a0") const UWORD* Temp, __reg("a1") UBYTE* Planar);
extern void StartC2PPlane2Asm(__reg("a0") const UWORD* Temp, __reg("a1") UBYTE* Planar);
extern void StartC2PPlane0Asm(__reg("a0") const UWORD* Temp, __reg("a1") UBYTE* Planar);
extern void BuildTextureOffsetsSliceAsm(__reg("a0") const struct RotoFrameStateTag* Frame, __reg("a1") UWORD* Offsets);
extern void RenderPhase0TempOffsetSliceAsm(__reg("a0") const UWORD* Offsets, __reg("a1") UWORD* TempFrame);

typedef void (*RunC2PExtractAsmFn)(__reg("a0") const UWORD* Temp, __reg("a1") UBYTE* Planar);
typedef void (*StartC2PPlaneAsmFn)(__reg("a0") const UWORD* Temp, __reg("a1") UBYTE* Planar);
typedef void (*BuildTextureOffsetsSliceAsmFn)(__reg("a0") const struct RotoFrameStateTag* Frame, __reg("a1") UWORD* Offsets);
typedef void (*RenderPhase0TempOffsetSliceAsmFn)(__reg("a0") const UWORD* Offsets, __reg("a1") UWORD* TempFrame);

/* Call the larger ASM entry points indirectly so vbcc does not emit short
 * PC-relative calls that can overflow at link time on larger builds. */
static volatile RunC2PExtractAsmFn RunC2PExtractAsmCall = RunC2PExtractAsm;
static volatile StartC2PPlaneAsmFn StartC2PPlane3AsmCall = StartC2PPlane3Asm;
static volatile StartC2PPlaneAsmFn StartC2PPlane1AsmCall = StartC2PPlane1Asm;
static volatile StartC2PPlaneAsmFn StartC2PPlane2AsmCall = StartC2PPlane2Asm;
static volatile StartC2PPlaneAsmFn StartC2PPlane0AsmCall = StartC2PPlane0Asm;
static volatile BuildTextureOffsetsSliceAsmFn BuildTextureOffsetsSliceAsmCall = BuildTextureOffsetsSliceAsm;
static volatile RenderPhase0TempOffsetSliceAsmFn RenderPhase0TempOffsetSliceAsmCall = RenderPhase0TempOffsetSliceAsm;

#define TEXTURE_FILENAME                "gfx/128x128_ham.iff"
#define TEXTURE_SOURCE_WIDTH            128
#define TEXTURE_SOURCE_HEIGHT           128
#define TEXTURE_WIDTH                   TEXTURE_SOURCE_WIDTH
#define TEXTURE_HEIGHT                  TEXTURE_SOURCE_HEIGHT
#define TEXTURE_WORD_COUNT              ((ULONG)TEXTURE_WIDTH * (ULONG)TEXTURE_HEIGHT)

#define ROTO_COLUMNS                    28
#define ROTO_ROWS                       48
#define ROTO_CHUNK_ROWS                 4
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
#define ROTO_OFFSET_SLICE_WORDS         ((UWORD)(ROTO_COLUMNS * ROTO_CHUNK_ROWS))
#define ROTO_OFFSET_FRAME_WORDS         ((UWORD)(ROTO_COLUMNS * ROTO_ROWS))
#define ROTO_OFFSET_FRAME_BYTES         ((ULONG)ROTO_OFFSET_FRAME_WORDS * (ULONG)sizeof(UWORD))
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
#define DMACONR_ADDR                   0x0002
#define DMACON_ADDR                    0x0096
#define DMAF_SETCLR_WORD               0x8000
#define DMAF_MASTER_WORD               0x0200
#define DMAF_BLITPRI_WORD              0x0400
#define DMAF_BLITTER_WORD              0x0040
#define BLTAFWM_ADDR                    0x0044
#define BLTALWM_ADDR                    0x0046
#define BLTBMOD_ADDR                    0x0062
#define BLTAMOD_ADDR                    0x0064
#define BLTDMOD_ADDR                    0x0066
#define BLTCDAT_ADDR                    0x0070
#define CUSTOM_UWORD(addr)             (*(volatile UWORD*)((CUSTOM_BASE_ADDR) + (addr)))

typedef struct RotoFrameStateTag
{
    WORD DuDx;
    WORD DvDx;
    WORD StartU;
    WORD StartV;
} RotoFrameState;

typedef char RotoFrameStateSizeMustBe8[(sizeof(RotoFrameState) == 8) ? 1 : -1];

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

static ULONG* TextureDirectBase = NULL;
static ULONG TextureDirectBaseSize = 0;
UBYTE* TextureDirectBaseMid = NULL;
ULONG* Ham7Phase0GreenPack = NULL;
static ULONG Ham7Phase0GreenPackSize = 0;
static UWORD DisplayPalette[SCREEN_COLORS];
static UBYTE* ScreenBuffers[BUFFER_COUNT] = { NULL, NULL };
static UBYTE* C2PTempBuffers[BUFFER_COUNT] = { NULL, NULL };
static ULONG C2PTempBufferSize = 0;
static UWORD* FrameOffsetBuffers[BUFFER_COUNT] = { NULL, NULL };
static ULONG FrameOffsetBufferSize = 0;
static UWORD* CopperList = NULL;
static ULONG CopperListSize = 0;
static UWORD BPLPTH_Idx[ROTO_DMA_BITPLANES];
static UWORD BPLPTL_Idx[ROTO_DMA_BITPLANES];
static RotoFrameState* FrameStates = NULL;
static ULONG FrameStatesSize = 0;
static RotoFrameState* CurrentFrameState = NULL;
static RotoFrameState* FrameStatesEnd = NULL;

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

#define HAM7_PHASE0_GREEN_PACK_ENTRIES  256UL

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

static void AllocPhase0PackedTables(void)
{
    /* Keep the tiny green transition table in explicit CPU memory.
     * The direct renderer touches it on every logical texel. */
    Ham7Phase0GreenPackSize = HAM7_PHASE0_GREEN_PACK_ENTRIES * (ULONG)sizeof(ULONG);
    Ham7Phase0GreenPack = (ULONG*)lwmf_AllocCpuMem(Ham7Phase0GreenPackSize, MEMF_CLEAR);
}

static void BuildPhase0PackedTables(void)
{
    for (UWORD Prev = 0; Prev < 16U; ++Prev)
    {
        for (UWORD TargetG = 0; TargetG < 16U; ++TargetG)
        {
            const UBYTE EncodedGreen = EncodeGreenPhase0Nibble((UBYTE)Prev, (UBYTE)TargetG);
            const UWORD GreenWord = Ham7Phase0GreenWord[EncodedGreen];
            Ham7Phase0GreenPack[(Prev << 4) | TargetG] = (((ULONG)GreenWord) << 16) | ((ULONG)EncodedGreen << 6);
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
    /* Store one direct 32-bit texel descriptor per decoded texture texel.
     * High word = final red/blue base word, low word = green-pack byte offset.
     * A second centered pointer lets the 68000 reach the full 64 KiB table with
     * one signed 16-bit indexed address from the offset-based render hot path. */
    TextureDirectBaseSize = TEXTURE_WORD_COUNT * (ULONG)sizeof(ULONG);
    TextureDirectBase = (ULONG*)lwmf_AllocCpuMem(TextureDirectBaseSize, MEMF_CLEAR);
    TextureDirectBaseMid = ((UBYTE*)TextureDirectBase) + (TextureDirectBaseSize / 2UL);
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
                {
                    const UBYTE TargetR = (UBYTE)((OutRGB >> 8) & 0x000FU);
                    const UBYTE TargetG = (UBYTE)((OutRGB >> 4) & 0x000FU);
                    const UBYTE TargetB = (UBYTE)(OutRGB & 0x000FU);
                    const UWORD RBWord = (UWORD)(Ham7Phase0RedWord[TargetR] | Ham7Phase0BlueWord[TargetB]);
                    const UWORD GreenOffset = (UWORD)(TargetG << 2);
                    TextureDirectBase[TexIndex] = (((ULONG)RBWord) << 16) | (ULONG)GreenOffset;
                }
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
    /* Keep one compact 8-byte header per animation frame.
     * The direct renderer now carries the row starts continuously across the full 48-row frame,
     * so no per-chunk start pairs need to be stored anymore. */
    FrameStatesSize = 256UL * (ULONG)sizeof(RotoFrameState);
    FrameStates = (RotoFrameState*)lwmf_AllocCpuMem(FrameStatesSize, MEMF_CLEAR);

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
        RotoFrameState* State = &FrameStates[Frame];

        State->DuDx = DuDx;
        State->DvDx = DvDx;
        State->StartU = (WORD)((WORD)ROTO_CENTER_U + MoveX + (WORD)StartUOffset);
        State->StartV = (WORD)((WORD)ROTO_CENTER_V + MoveY + (WORD)StartVOffset);
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

static void InitFrameOffsetBuffers(void)
{
    FrameOffsetBufferSize = ROTO_OFFSET_FRAME_BYTES;

    for (UWORD i = 0; i < BUFFER_COUNT; ++i)
    {
        FrameOffsetBuffers[i] = (UWORD*)lwmf_AllocCpuMem(FrameOffsetBufferSize, MEMF_CLEAR);
    }
}

static void BuildSliceState(const RotoFrameState* Frame, UWORD SliceIndex, RotoFrameState* SliceState)
{
    const LONG SliceRow = (LONG)SliceIndex * (LONG)ROTO_CHUNK_ROWS;

    SliceState->DuDx = Frame->DuDx;
    SliceState->DvDx = Frame->DvDx;
    SliceState->StartU = (WORD)((LONG)Frame->StartU + (SliceRow * (LONG)Frame->DvDx));
    SliceState->StartV = (WORD)((LONG)Frame->StartV - (SliceRow * (LONG)Frame->DuDx));
}

static void BuildOffsetSlice(const RotoFrameState* Frame, UWORD SliceIndex, UWORD* Offsets)
{
    RotoFrameState SliceState;
    BuildSliceState(Frame, SliceIndex, &SliceState);
    (*BuildTextureOffsetsSliceAsmCall)(&SliceState, Offsets);
}

static void BuildOffsetFrame(const RotoFrameState* Frame, UWORD* Offsets)
{
    for (UWORD Slice = 0; Slice < ROTO_CHUNK_COUNT; ++Slice)
    {
        BuildOffsetSlice(Frame, Slice, Offsets + ((ULONG)Slice * (ULONG)ROTO_OFFSET_SLICE_WORDS));
    }
}

static RotoFrameState* NextFrameState(RotoFrameState* State)
{
    ++State;

    if (State == FrameStatesEnd)
    {
        State = FrameStates;
    }

    return State;
}

static void EnableBlitterPriority(void)
{
    CUSTOM_UWORD(DMACON_ADDR) = (UWORD)(DMAF_SETCLR_WORD | DMAF_BLITPRI_WORD);
}

static void DisableBlitterPriority(void)
{
    CUSTOM_UWORD(DMACON_ADDR) = DMAF_BLITPRI_WORD;
}

static void InitC2PBlitterStatic(void)
{
    CUSTOM_UWORD(BLTAFWM_ADDR) = 0xFFFFU;
    CUSTOM_UWORD(BLTALWM_ADDR) = 0xFFFFU;
    CUSTOM_UWORD(BLTBMOD_ADDR) = 6U;
    CUSTOM_UWORD(BLTAMOD_ADDR) = 6U;
    CUSTOM_UWORD(BLTDMOD_ADDR) = 0U;
    CUSTOM_UWORD(BLTCDAT_ADDR) = 0x0F0FU;
}

static void RenderTempSlice(const UWORD* Offsets, UBYTE* TempBuffer)
{
    (*RenderPhase0TempOffsetSliceAsmCall)(Offsets, (UWORD*)TempBuffer);
}

static void RenderTempFrame(const UWORD* Offsets, UBYTE* TempBuffer)
{
    for (UWORD Slice = 0; Slice < ROTO_CHUNK_COUNT; ++Slice)
    {
        RenderTempSlice(Offsets + ((ULONG)Slice * (ULONG)ROTO_OFFSET_SLICE_WORDS),
                        TempBuffer + ((ULONG)Slice * ROTO_CHUNK_BYTES));
    }
}

static UBYTE BlitterBusy(void)
{
    return (UBYTE)((CUSTOM_UWORD(DMACONR_ADDR) & (1U << 14)) != 0U);
}

static void BlitFrameSync(const UBYTE* TempBuffer, UBYTE* Screen)
{
    EnableBlitterPriority();
    (*RunC2PExtractAsmCall)((const UWORD*)TempBuffer, Screen);
    DisableBlitterPriority();
}

/* Copper repeats each logical row four times. The modulo stays at -fetch-bytes
 * for the first three visible scanlines and returns to zero on the fourth one,
 * so the DMA pointer advances only once per 4-line macro row. */
static UWORD DisplayLineModulo(UWORD DisplayY)
{
    return ((DisplayY & (ROTO_PIXEL_SCALE - 1U)) == (ROTO_PIXEL_SCALE - 1U)) ? 0x0000U : ROTO_REPEAT_MODULO;
}

/* Build one compact Copper list for the HAM display window.
 *
 * Layout of the list:
 * - global display window / fetch timing setup
 * - HAM mode and the fixed control words on bitplanes 5/6
 * - patch points for the four DMA bitplane pointers
 * - palette upload
 * - one wait+modulo update per visible scanline to vertically repeat rows
 */
static void Init_CopperList(void)
{
    const ULONG CopperWords = 24UL + (ULONG)(4 * ROTO_DMA_BITPLANES) + (ULONG)(SCREEN_COLORS * 2) + ((ULONG)(ROTO_DISPLAY_HEIGHT - 1U) * 6UL) + 2UL;

    CopperListSize = CopperWords * sizeof(UWORD);
    CopperList = (UWORD*)AllocMem(CopperListSize, MEMF_CHIP | MEMF_CLEAR);

    UWORD Index = 0;

    /* Global display window and DMA fetch timing for the centered roto area. */
    CopperList[Index++] = 0x008E; CopperList[Index++] = ROTO_DIWSTRT;
    CopperList[Index++] = 0x0090; CopperList[Index++] = ROTO_DIWSTOP;
    CopperList[Index++] = 0x0092; CopperList[Index++] = ROTO_DDFSTRT;
    CopperList[Index++] = 0x0094; CopperList[Index++] = ROTO_DDFSTOP;

    /* Enable HAM with four DMA planes and preload the line modulo for scanline 0. */
    CopperList[Index++] = 0x0100; CopperList[Index++] = HAM_BPLCON0;
    CopperList[Index++] = 0x0102; CopperList[Index++] = 0x0000;
    CopperList[Index++] = 0x0104; CopperList[Index++] = 0x0000;
    CopperList[Index++] = 0x0108; CopperList[Index++] = DisplayLineModulo(0);
    CopperList[Index++] = 0x010A; CopperList[Index++] = DisplayLineModulo(0);

    /* Feed the fixed HAM control pattern through BPL5DAT/BPL6DAT. */
    CopperList[Index++] = 0x0118; CopperList[Index++] = HAM_CONTROL_WORD_P5;
    CopperList[Index++] = 0x011A; CopperList[Index++] = HAM_CONTROL_WORD_P6;

    /* Reserve patch points for the four DMA bitplane pointers. */
    for (UWORD Plane = 0; Plane < ROTO_DMA_BITPLANES; ++Plane)
    {
        CopperList[Index++] = (UWORD)(0x00E0 + (Plane * 4));
        BPLPTH_Idx[Plane] = Index;
        CopperList[Index++] = 0x0000;

        CopperList[Index++] = (UWORD)(0x00E2 + (Plane * 4));
        BPLPTL_Idx[Plane] = Index;
        CopperList[Index++] = 0x0000;
    }

    /* Upload the base palette used by the HAM bootstrap/control phase. */
    for (UWORD c = 0; c < SCREEN_COLORS; ++c)
    {
        CopperList[Index++] = (UWORD)(0x0180 + (c * 2));
        CopperList[Index++] = DisplayPalette[c];
    }

    /* After each visible scanline, wait for the next line and update BPL1MOD/BPL2MOD.
     * This is what stretches one logical row over four display lines without duplicating memory. */
    for (UWORD DisplayY = 1; DisplayY < ROTO_DISPLAY_HEIGHT; ++DisplayY)
    {
        const UWORD WaitVPos = (UWORD)(ROTO_VPOS_START + DisplayY);
        CopperList[Index++] = (UWORD)(((WaitVPos & 0x00FFU) << 8) | 0x0007U);
        CopperList[Index++] = 0xFFFE;
        CopperList[Index++] = 0x0108; CopperList[Index++] = DisplayLineModulo(DisplayY);
        CopperList[Index++] = 0x010A; CopperList[Index++] = DisplayLineModulo(DisplayY);
    }

    /* Copper end marker. */
    CopperList[Index++] = 0xFFFF;
    CopperList[Index++] = 0xFFFE;

    /* Point COP1LC at the freshly built list. */
    *COP1LC = (ULONG)CopperList;
}

/* Patch the four bitplane pointers inside the Copper list to the selected screen buffer.
 * The list structure stays constant; only these pointer words change per frame. */
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

    for (UWORD i = 0; i < BUFFER_COUNT; ++i)
    {
        FreeMem(FrameOffsetBuffers[i], FrameOffsetBufferSize);
        FrameOffsetBuffers[i] = NULL;
    }

    FrameOffsetBufferSize = 0;

    FreeMem(CopperList, CopperListSize);
    CopperList = NULL;
    CopperListSize = 0;
    FreeMem(TextureDirectBase, TextureDirectBaseSize);
    TextureDirectBase = NULL;
    TextureDirectBaseSize = 0;
    TextureDirectBaseMid = NULL;

    FreeMem(Ham7Phase0GreenPack, Ham7Phase0GreenPackSize);
    Ham7Phase0GreenPack = NULL;
    Ham7Phase0GreenPackSize = 0;
    FreeMem(FrameStates, FrameStatesSize);
    FrameStates = NULL;
    FrameStatesSize = 0;
    CurrentFrameState = NULL;
    FrameStatesEnd = NULL;

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

    /* Build the split 16-bit render tables first so texture decode can store
     * the predecoded red/blue words and green offsets per texel. */
    AllocPhase0PackedTables();
    BuildPhase0PackedTables();
    InitTexture();
    BuildFrameStates();
    FrameStatesEnd = FrameStates + 256;
    CurrentFrameState = &FrameStates[0];

    InitFrameOffsetBuffers();
    InitScreenBuffers();
    Init_CopperList();

    InitC2PBlitterStatic();

    /* Prime the pipeline:
     * - offset/temp buffer 0 gets frame 0 and is blitted immediately
     * - offset/temp buffer 1 gets frame 1 and becomes the first ready temp frame
     * - offset buffer 0 is then reused to prebuild frame 2 before entering the main loop */
    BuildOffsetFrame(CurrentFrameState, FrameOffsetBuffers[0]);
    RenderTempFrame(FrameOffsetBuffers[0], C2PTempBuffers[0]);
    BlitFrameSync(C2PTempBuffers[0], ScreenBuffers[0]);
    Update_BitplanePointers(0);

    CurrentFrameState = NextFrameState(CurrentFrameState);
    BuildOffsetFrame(CurrentFrameState, FrameOffsetBuffers[1]);
    RenderTempFrame(FrameOffsetBuffers[1], C2PTempBuffers[1]);

    RotoFrameState* RenderFramePtr = NextFrameState(CurrentFrameState);
    BuildOffsetFrame(RenderFramePtr, FrameOffsetBuffers[0]);
    RotoFrameState* BuildFramePtr = NextFrameState(RenderFramePtr);

    lwmf_TakeOverOS();
    CUSTOM_UWORD(DMACON_ADDR) = (UWORD)(DMAF_SETCLR_WORD | DMAF_MASTER_WORD | DMAF_BLITTER_WORD);
    InitC2PBlitterStatic();

    UWORD DrawBuffer = 1;
    UWORD ReadyTemp = 1;
    UWORD RenderTemp = 0;
    UWORD RenderOffset = 0;
    UWORD BuildOffset = 1;

#define RENDER_BUILD_SLICE(SLICE_INDEX) \
    do \
    { \
        RenderTempSlice(FrameOffsetBuffers[RenderOffset] + ((ULONG)(SLICE_INDEX) * (ULONG)ROTO_OFFSET_SLICE_WORDS), \
                        C2PTempBuffers[RenderTemp] + ((ULONG)(SLICE_INDEX) * ROTO_CHUNK_BYTES)); \
        BuildOffsetSlice(BuildFramePtr, (SLICE_INDEX), \
                         FrameOffsetBuffers[BuildOffset] + ((ULONG)(SLICE_INDEX) * (ULONG)ROTO_OFFSET_SLICE_WORDS)); \
    } while (0)

    while (*CIAA_PRA & 0x40)
    {
        UWORD Slice = 0;

        (*StartC2PPlane3AsmCall)((const UWORD*)C2PTempBuffers[ReadyTemp], ScreenBuffers[DrawBuffer]);

        RENDER_BUILD_SLICE(Slice);
        ++Slice;

        while ((Slice < (ROTO_CHUNK_COUNT - 3U)) && BlitterBusy())
        {
            RENDER_BUILD_SLICE(Slice);
            ++Slice;
        }

        if (BlitterBusy())
        {
            lwmf_WaitBlitter();
        }

        (*StartC2PPlane1AsmCall)((const UWORD*)C2PTempBuffers[ReadyTemp], ScreenBuffers[DrawBuffer]);

        RENDER_BUILD_SLICE(Slice);
        ++Slice;

        while ((Slice < (ROTO_CHUNK_COUNT - 2U)) && BlitterBusy())
        {
            RENDER_BUILD_SLICE(Slice);
            ++Slice;
        }

        if (BlitterBusy())
        {
            lwmf_WaitBlitter();
        }

        (*StartC2PPlane2AsmCall)((const UWORD*)C2PTempBuffers[ReadyTemp], ScreenBuffers[DrawBuffer]);

        RENDER_BUILD_SLICE(Slice);
        ++Slice;

        while ((Slice < (ROTO_CHUNK_COUNT - 1U)) && BlitterBusy())
        {
            RENDER_BUILD_SLICE(Slice);
            ++Slice;
        }

        if (BlitterBusy())
        {
            lwmf_WaitBlitter();
        }

        (*StartC2PPlane0AsmCall)((const UWORD*)C2PTempBuffers[ReadyTemp], ScreenBuffers[DrawBuffer]);

        while (Slice < ROTO_CHUNK_COUNT)
        {
            RENDER_BUILD_SLICE(Slice);
            ++Slice;
        }

        CurrentFrameState = RenderFramePtr;
        RenderFramePtr = BuildFramePtr;
        BuildFramePtr = NextFrameState(BuildFramePtr);

        EnableBlitterPriority();
        lwmf_WaitVertBlank();
        lwmf_WaitBlitter();
        DisableBlitterPriority();

        Update_BitplanePointers(DrawBuffer);
        DrawBuffer ^= 1;

        {
            const UWORD TempSwap = ReadyTemp;
            ReadyTemp = RenderTemp;
            RenderTemp = TempSwap;
        }

        {
            const UWORD OffsetSwap = RenderOffset;
            RenderOffset = BuildOffset;
            BuildOffset = OffsetSwap;
        }
    }

#undef RENDER_BUILD_SLICE

    Cleanup_All();
    return 0;
}
