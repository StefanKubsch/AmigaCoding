//**********************************************************************
//* Rocklobster-inspired 4x4 Copper Chunky Shear-Rotozoomer            *
//* 5 Bitplanes, 32 colors, 48 columns                                 *
//* Amiga 500 OCS                                                      *
//*                                                                    *
//* The outer framework stays identical to the original source:        *
//*  - same Init/Draw/Cleanup flow                                     *
//*  - same copper-chunky 4x4 output path                              *
//*  - same 5 bitplane / 32 color display                              *
//*                                                                    *
//* Internally the direct affine sampler is replaced by a dedicated    *
//* two-pass shear pipeline that follows the Planet-Rocklobster idea:  *
//*  - 4 pre-rotated textures in 90 degree steps                       *
//*  - residual angle limited to +/-45 degree                          *
//*  - offscreen shear buffer that is wider than the visible area      *
//*  - final pass back into the existing copper-chunky framework       *
//*                                                                    *
//* Pass decomposition for source = M * screen + center:               *
//*                                                                    *
//*   M = A * B                                                        *
//*   A = [ 1  kx ]    (x-shear + y-scale)                             *
//*       [ 0  sy ]                                                    *
//*   B = [ sx  0 ]    (x-scale + y-shear)                             *
//*       [ ky  1 ]                                                    *
//*                                                                    *
//* with                                                               *
//*   kx = -zoom * sin(phi)                                            *
//*   sy =  zoom * cos(phi)                                            *
//*   sx =  zoom / cos(phi)                                            *
//*   ky =  tan(phi)                                                   *
//*                                                                    *
//* phi is the residual angle after switching to one of the four       *
//* pre-rotated textures.                                              *
//*                                                                    *
//* (C) 2020-2026 by Stefan Kubsch/Deep4                               *
//* Reworked to a shear pipeline by OpenAI                             *
//* Project for vbcc                                                   *
//*                                                                    *
//* Compile & link with:                                               *
//* make_Rotozoomer.cmd                                                *
//*                                                                    *
//* Quit with mouse click                                              *
//**********************************************************************

#include "lwmf/lwmf.h"

// Enable (set to 1) for debugging
// When enabled, timing/load will be displayed via COLOR00 changes.
#define DEBUG                  0

#if DEBUG
    #define DBG_COLOR(c) (*COLOR00 = (c))
#else
    #define DBG_COLOR(c) ((void)0)
#endif

typedef struct RotoAsmParams
{
    const UBYTE *Chunky;
    UBYTE       **RowPtr;
    const UBYTE *PairExpand;
} RotoAsmParams;

extern void DrawRotoBodyAsm(__reg("a0") const struct RotoAsmParams *Params);

// =====================================================================
// Effect constants
// =====================================================================

#define TEXTURE_FILENAME         "gfx/128x128_5bpl_2.iff"
#define TEXTURE_SOURCE_WIDTH     128
#define TEXTURE_SOURCE_HEIGHT    128
#define TEXTURE_WIDTH            TEXTURE_SOURCE_WIDTH
#define TEXTURE_HEIGHT           TEXTURE_SOURCE_HEIGHT
#define TEXTURE_MASK_X           (TEXTURE_WIDTH - 1)
#define TEXTURE_MASK_Y           (TEXTURE_HEIGHT - 1)

#define SCREEN_COLORS            32
#define TEXTURE_COLOR_BASE       1

// Base zoom in texels per logical output pixel (8.8 fixed point)
#define ROTO_ZOOM_BASE           384
#define ROTO_ZOOM_AMPLITUDE      128
#define ROTO_ZOOM_SPEED          1

#define CHUNKY_PIXEL_SIZE        4
#define ROTO_COLUMNS             48
#define ROTO_ROWS                48
#define ROTO_PAIR_COUNT          (ROTO_COLUMNS / 2)
#define ROTO_DISPLAY_WIDTH       (ROTO_COLUMNS * CHUNKY_PIXEL_SIZE)
#define ROTO_DISPLAY_HEIGHT      (ROTO_ROWS * CHUNKY_PIXEL_SIZE)

#define ROTO_HALF_COLUMNS        (ROTO_COLUMNS / 2)
#define ROTO_HALF_ROWS           (ROTO_ROWS / 2)
#define ROTO_ZOOM_STEPS          32

// Wider-than-visible intermediate just like the Rocklobster approach.
// 160 gives enough horizontal headroom for 48 columns at zoom 2.0 and
// residual angles up to +/-45 degree.
#define SHEAR_STAGE1_WIDTH       160
#define SHEAR_STAGE1_HEIGHT      (ROTO_ROWS + ROTO_COLUMNS)
#define SHEAR_STAGE1_HALF_W      (SHEAR_STAGE1_WIDTH / 2)
#define SHEAR_STAGE1_HALF_H      (SHEAR_STAGE1_HEIGHT / 2)

#define ROTO_START_X             ((((SCREENWIDTH - ROTO_DISPLAY_WIDTH) >> 1)) & ~7)
#define ROTO_START_BYTE          (ROTO_START_X >> 3)

#define INTERLEAVED_STRIDE       (BYTESPERROW * NUMBEROFBITPLANES)
#define INTERLEAVEDMOD           (BYTESPERROW * (NUMBEROFBITPLANES - 1))

#define ROTO_FETCH_WORDS         (ROTO_DISPLAY_WIDTH / 16)
#define ROTO_FETCH_BYTES         (ROTO_DISPLAY_WIDTH / 8)
#define ROTO_REPEAT_MOD          ((UWORD)(-(WORD)ROTO_FETCH_BYTES))
#define ROTO_ADVANCE_MOD         ((UWORD)(INTERLEAVED_STRIDE - ROTO_FETCH_BYTES))

#define VPOS_OFFSET              0x2C

/*
 * Keep the narrow 192-pixel lowres window, but place the 192 active lines
 * lower in the frame so the CPU gets more DMA-light scanlines immediately
 * after VBlank. The effect stays vertically centered inside the normal
 * 256-line PAL playfield area.
 */
#define ROTO_VPOS_START          (VPOS_OFFSET + ((SCREENHEIGHT - ROTO_DISPLAY_HEIGHT) / 2))
#define ROTO_VPOS_STOP           (ROTO_VPOS_START + ROTO_DISPLAY_HEIGHT)
#define ROTO_DIWSTRT             (UWORD)(((ROTO_VPOS_START & 0xFFu) << 8) | 0x00C1u)
#define ROTO_DIWSTOP             (UWORD)(((ROTO_VPOS_STOP  & 0xFFu) << 8) | 0x0081u)
#define ROTO_DDFSTRT             0x0058
#define ROTO_DDFSTOP             0x00B0

// Residual-angle decomposition table.
typedef struct
{
    WORD Pass1Kx;   // 8.8 texels per intermediate row
    WORD Pass1Sy;   // 8.8 texels per intermediate row
    WORD Pass2Sx;   // 8.8 intermediate X units per output pixel
    WORD Pass2Ky;   // 8.8 intermediate Y units per output pixel
} RotoDelta;

static WORD MoveTab[256];
static RotoDelta *DeltaTab = NULL;
static ULONG DeltaTabSize = 0;

// =====================================================================
// Values span 0..63, so signed values are obtained via (value - 32).
// =====================================================================

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

// =====================================================================
// Texture, tables and animation state
// =====================================================================

static UBYTE *TextureChunky = NULL;           // points to rotation 0 in the 4-rotation set
static ULONG TextureChunkySize = 0;          // one 128x128 texture
static ULONG TextureSetSize = 0;             // all 4 pre-rotations
static UBYTE *TextureRot[4] = { NULL, NULL, NULL, NULL };

static UBYTE *ShearStage1 = NULL;
static ULONG ShearStage1Size = 0;

static UBYTE *RotoChunky = NULL;
static ULONG RotoChunkySize = 0;

static UWORD TexturePalette[SCREEN_COLORS];
static UBYTE TextureColorBase = 0;

#define PAIR_EXPAND_STRIDE       1024u
#define PAIR_EXPAND_WORD_BYTES   (PAIR_EXPAND_STRIDE * sizeof(UWORD))
#define PAIR_EXPAND_PLANE01_OFF  0u
#define PAIR_EXPAND_PLANE23_OFF  (PAIR_EXPAND_PLANE01_OFF + PAIR_EXPAND_WORD_BYTES)
#define PAIR_EXPAND_PLANE4_OFF   (PAIR_EXPAND_PLANE23_OFF + PAIR_EXPAND_WORD_BYTES)
#define PAIR_EXPAND_TOTAL_BYTES  (PAIR_EXPAND_PLANE4_OFF + PAIR_EXPAND_STRIDE)

typedef struct PairExpandSet
{
    UWORD Plane01[PAIR_EXPAND_STRIDE];
    UWORD Plane23[PAIR_EXPAND_STRIDE];
    UBYTE Plane4[PAIR_EXPAND_STRIDE];
} PairExpandSet;

static PairExpandSet PairExpand;
static UBYTE *RotoRowPtr[2][ROTO_ROWS];

static UBYTE AnglePhase = 0;
static UBYTE ZoomPhase = 0;
static UBYTE MovePhaseX = 0;
static UBYTE MovePhaseY = 64;

// =====================================================================
// Texture loading and precomputation
// =====================================================================

static void BuildPairExpandTable(void)
{
    for (UWORD packed = 0; packed < PAIR_EXPAND_STRIDE; ++packed)
    {
        const UBYTE c0 = (UBYTE)(packed & 31u);
        const UBYTE c1 = (UBYTE)(packed >> 5u);

        const UBYTE b0 = (UBYTE)(((c0 & 0x01u) ? 0xF0u : 0x00u) | ((c1 & 0x01u) ? 0x0Fu : 0x00u));
        const UBYTE b1 = (UBYTE)(((c0 & 0x02u) ? 0xF0u : 0x00u) | ((c1 & 0x02u) ? 0x0Fu : 0x00u));
        const UBYTE b2 = (UBYTE)(((c0 & 0x04u) ? 0xF0u : 0x00u) | ((c1 & 0x04u) ? 0x0Fu : 0x00u));
        const UBYTE b3 = (UBYTE)(((c0 & 0x08u) ? 0xF0u : 0x00u) | ((c1 & 0x08u) ? 0x0Fu : 0x00u));
        const UBYTE b4 = (UBYTE)(((c0 & 0x10u) ? 0xF0u : 0x00u) | ((c1 & 0x10u) ? 0x0Fu : 0x00u));

        PairExpand.Plane01[packed] = (UWORD)(((UWORD)b1 << 8) | (UWORD)b0);
        PairExpand.Plane23[packed] = (UWORD)(((UWORD)b3 << 8) | (UWORD)b2);
        PairExpand.Plane4[packed] = b4;
    }
}

static void BuildChunkyTextureFromBitmap(struct lwmf_Image *RotoBitmap)
{
    const UBYTE PlaneCount = (RotoBitmap->Image.Depth > 5u) ? 5u : RotoBitmap->Image.Depth;
    const UWORD BytesPerRow = RotoBitmap->Image.BytesPerRow;
    const UWORD ColorCount = (UWORD)RotoBitmap->NumberOfColors;

    TextureChunkySize = (ULONG)TEXTURE_WIDTH * (ULONG)TEXTURE_HEIGHT;
    TextureSetSize = TextureChunkySize * 4u;
    TextureChunky = (UBYTE*)lwmf_AllocCpuMem(TextureSetSize, MEMF_CLEAR);

    TextureRot[0] = TextureChunky;
    TextureRot[1] = TextureChunky + TextureChunkySize;
    TextureRot[2] = TextureChunky + (TextureChunkySize * 2u);
    TextureRot[3] = TextureChunky + (TextureChunkySize * 3u);

    for (UWORD i = 0; i < SCREEN_COLORS; ++i)
    {
        TexturePalette[i] = 0x000u;
    }

    TextureColorBase = (ColorCount < SCREEN_COLORS) ? TEXTURE_COLOR_BASE : 0u;

    if (RotoBitmap->CRegs)
    {
        for (UWORD i = 0; i < ColorCount; ++i)
        {
            TexturePalette[i + TextureColorBase] = (UWORD)(RotoBitmap->CRegs[i] & 0x0FFFu);
        }
    }
    else
    {
        for (UWORD i = 0; i < ColorCount; ++i)
        {
            const UWORD V = (UWORD)((i * 15u) / ((ColorCount > 1u) ? (ColorCount - 1u) : 1u));
            TexturePalette[i + TextureColorBase] = (UWORD)((V << 8) | (V << 4) | V);
        }
    }

    for (UWORD y = 0; y < TEXTURE_SOURCE_HEIGHT; ++y)
    {
        UBYTE *Dst = TextureRot[0] + ((ULONG)y * (ULONG)TEXTURE_WIDTH);

        for (UWORD x = 0; x < TEXTURE_SOURCE_WIDTH; ++x)
        {
            const UBYTE Mask = (UBYTE)(1u << (7u - (x & 7u)));
            const UWORD ByteOffset = (UWORD)(x >> 3u);
            UBYTE Index = 0;

            for (UBYTE p = 0; p < PlaneCount; ++p)
            {
                const UBYTE *Plane = (const UBYTE*)RotoBitmap->Image.Planes[p];

                if (Plane[(ULONG)y * (ULONG)BytesPerRow + ByteOffset] & Mask)
                {
                    Index |= (UBYTE)(1u << p);
                }
            }

            Dst[x] = (UBYTE)(Index + TextureColorBase);
        }
    }
}

static void RotateTexture90CW(const UBYTE *Src, UBYTE *Dst)
{
    for (UWORD y = 0; y < TEXTURE_HEIGHT; ++y)
    {
        for (UWORD x = 0; x < TEXTURE_WIDTH; ++x)
        {
            const UWORD DstX = (UWORD)(TEXTURE_WIDTH - 1u - y);
            const UWORD DstY = x;
            Dst[(ULONG)DstY * (ULONG)TEXTURE_WIDTH + DstX] = Src[(ULONG)y * (ULONG)TEXTURE_WIDTH + x];
        }
    }
}

static void BuildRotatedTextures(void)
{
    RotateTexture90CW(TextureRot[0], TextureRot[1]);
    RotateTexture90CW(TextureRot[1], TextureRot[2]);
    RotateTexture90CW(TextureRot[2], TextureRot[3]);
}

// =====================================================================
// Rocklobster-style shear decomposition tables
// =====================================================================

static void BuildMoveTable(void)
{
    for (UWORD i = 0; i < 256; ++i)
    {
        MoveTab[i] = (WORD)((64 << 8) + (((WORD)SinTab256[i] - 32) << 7));
    }
}

static void BuildDeltaTable(void)
{
    for (WORD r = -32; r < 32; ++r)
    {
        const UBYTE Angle = (UBYTE)r;
        const WORD SinV = (WORD)SinTab256[Angle] - 32;
        const WORD CosV = (WORD)SinTab256[(UBYTE)(Angle + 64u)] - 32;
        const WORD Sin8 = (WORD)(((LONG)SinV << 8) / 32L);
        const WORD Cos8 = (WORD)(((LONG)CosV << 8) / 32L);

        for (UWORD z = 0; z < ROTO_ZOOM_STEPS; ++z)
        {
            const WORD ZoomMod = (WORD)(((WORD)z << 1) - 32);
            const WORD Zoom = (WORD)(ROTO_ZOOM_BASE + ((ZoomMod * ROTO_ZOOM_AMPLITUDE) >> 5));
            RotoDelta *D = &DeltaTab[(ULONG)(r + 32) * ROTO_ZOOM_STEPS + z];

            D->Pass1Kx = (WORD)(-(((LONG)Zoom * (LONG)Sin8) >> 8));
            D->Pass1Sy = (WORD)((((LONG)Zoom * (LONG)Cos8) >> 8));
            D->Pass2Sx = (WORD)(((LONG)Zoom << 8) / (LONG)Cos8);
            D->Pass2Ky = (WORD)(((LONG)Sin8 << 8) / (LONG)Cos8);
        }
    }
}

static void MapCenterToRotatedTexture(UBYTE TextureIndex, WORD *CenterU, WORD *CenterV)
{
    /*
     * Use the maximum in 8.8 fixed point, not the maximum integer texel index.
     *
     * For a 128-wide texture the mirrored coordinate must be computed against
     * 32767 (= (128 << 8) - 1), not 32512 (= 127 << 8). Otherwise any source
     * position with a non-zero fractional part lands one texel early after the
     * 90/180/270-degree remap, which shows up as a visible jump at quadrant
     * boundaries.
     */
    const WORD MaxU = (WORD)((((ULONG)TEXTURE_WIDTH) << 8) - 1u);
    const WORD MaxV = (WORD)((((ULONG)TEXTURE_HEIGHT) << 8) - 1u);
    const WORD U0 = *CenterU;
    const WORD V0 = *CenterV;

    switch (TextureIndex & 3u)
    {
        case 0:
            break;

        case 1:
            *CenterU = (WORD)(MaxU - V0);
            *CenterV = U0;
            break;

        case 2:
            *CenterU = (WORD)(MaxU - U0);
            *CenterV = (WORD)(MaxV - V0);
            break;

        default:
            *CenterU = V0;
            *CenterV = (WORD)(MaxV - U0);
            break;
    }
}

static const RotoDelta *ResolveFrameDelta(UBYTE Angle, UBYTE ZoomIndex, UBYTE *TextureIndex)
{
    const UBYTE Quadrant = (UBYTE)((((UWORD)Angle + 32u) >> 6u) & 3u);
    const UBYTE BaseAngle = (UBYTE)(Quadrant << 6u);
    WORD Residual = (WORD)Angle - (WORD)BaseAngle;

    if (Residual > 127)
    {
        Residual -= 256;
    }

    if (Residual < -32)
    {
        Residual += 64;
    }
    else if (Residual > 31)
    {
        Residual -= 64;
    }

    /* TextureRot[] is built clockwise, so use the inverse 90-degree base step here. */
    *TextureIndex = (UBYTE)((4u - Quadrant) & 3u);
    return &DeltaTab[(ULONG)(Residual + 32) * ROTO_ZOOM_STEPS + ZoomIndex];
}

static void BuildRowPointerTable(void)
{
    for (UBYTE Buffer = 0; Buffer < 2u; ++Buffer)
    {
        UBYTE *Base = (UBYTE*)ScreenBitmap[Buffer]->Planes[0];

        for (UWORD y = 0; y < ROTO_ROWS; ++y)
        {
            RotoRowPtr[Buffer][y] = Base + ((ULONG)y * INTERLEAVED_STRIDE) + ROTO_START_BYTE;
        }
    }
}

// =====================================================================
// Shear renderer
// =====================================================================

static void RenderShearPass1(const UBYTE *Texture, const RotoDelta *D, WORD CenterU, WORD CenterV)
{
    for (WORD y = 0; y < SHEAR_STAGE1_HEIGHT; ++y)
    {
        UBYTE *Dst = ShearStage1 + ((ULONG)y * SHEAR_STAGE1_WIDTH);
        const WORD Fy = (WORD)(y - SHEAR_STAGE1_HALF_H);
        LONG SrcX = (LONG)CenterU - ((LONG)SHEAR_STAGE1_HALF_W << 8) + ((LONG)D->Pass1Kx * (LONG)Fy);
        const LONG SrcY = (LONG)CenterV + ((LONG)D->Pass1Sy * (LONG)Fy);
        const UBYTE *TexRow = Texture + (((ULONG)((SrcY >> 8) & TEXTURE_MASK_Y)) * TEXTURE_WIDTH);

        for (WORD x = 0; x < SHEAR_STAGE1_WIDTH; ++x)
        {
            Dst[x] = TexRow[(UWORD)((SrcX >> 8) & TEXTURE_MASK_X)];
            SrcX += 0x100;
        }
    }
}

static void RenderShearPass2(const RotoDelta *D)
{
    for (WORD y = 0; y < ROTO_ROWS; ++y)
    {
        UBYTE *Dst = RotoChunky + ((ULONG)y * ROTO_COLUMNS);
        const WORD Fy = (WORD)(y - ROTO_HALF_ROWS);
        LONG StageX = ((LONG)SHEAR_STAGE1_HALF_W << 8) - ((LONG)ROTO_HALF_COLUMNS * (LONG)D->Pass2Sx);
        LONG StageY = ((LONG)SHEAR_STAGE1_HALF_H << 8) + ((LONG)Fy << 8) - ((LONG)ROTO_HALF_COLUMNS * (LONG)D->Pass2Ky);

        for (WORD x = 0; x < ROTO_COLUMNS; ++x)
        {
            const WORD Ix = (WORD)(StageX >> 8);
            const WORD Iy = (WORD)(StageY >> 8);

            if (((UWORD)Ix < SHEAR_STAGE1_WIDTH) && ((UWORD)Iy < SHEAR_STAGE1_HEIGHT))
            {
                Dst[x] = ShearStage1[(ULONG)Iy * SHEAR_STAGE1_WIDTH + (ULONG)Ix];
            }
            else
            {
                Dst[x] = 0u;
            }

            StageX += (LONG)D->Pass2Sx;
            StageY += (LONG)D->Pass2Ky;
        }
    }
}

void Init_RotoZoomer(void)
{
    struct lwmf_Image *RotoBitmap;

    RotoBitmap = lwmf_LoadImage(TEXTURE_FILENAME);

    DeltaTabSize = sizeof(RotoDelta) * 64u * ROTO_ZOOM_STEPS;
    DeltaTab = (RotoDelta*)lwmf_AllocCpuMem(DeltaTabSize, MEMF_CLEAR);

    ShearStage1Size = (ULONG)SHEAR_STAGE1_WIDTH * (ULONG)SHEAR_STAGE1_HEIGHT;
    ShearStage1 = (UBYTE*)lwmf_AllocCpuMem(ShearStage1Size, MEMF_CLEAR);

    RotoChunkySize = (ULONG)ROTO_COLUMNS * (ULONG)ROTO_ROWS;
    RotoChunky = (UBYTE*)lwmf_AllocCpuMem(RotoChunkySize, MEMF_CLEAR);

    BuildChunkyTextureFromBitmap(RotoBitmap);
    lwmf_DeleteImage(RotoBitmap);

    BuildRotatedTextures();
    BuildPairExpandTable();
    BuildMoveTable();
    BuildDeltaTable();
    BuildRowPointerTable();

    AnglePhase = 0;
    ZoomPhase  = 0;
    MovePhaseX = 0;
    MovePhaseY = 64;
}

void Draw_RotoZoomer(UBYTE Buffer)
{
    RotoAsmParams Params;
    const UBYTE ZoomIndex = (UBYTE)(SinTab256[ZoomPhase] >> 1);
    UBYTE TextureIndex;
    const RotoDelta *D = ResolveFrameDelta(AnglePhase, ZoomIndex, &TextureIndex);
    WORD CenterU = MoveTab[MovePhaseX];
    WORD CenterV = MoveTab[MovePhaseY];

    MapCenterToRotatedTexture(TextureIndex, &CenterU, &CenterV);

    DBG_COLOR(0xF00);          /* red = pass 1 */
    RenderShearPass1(TextureRot[TextureIndex], D, CenterU, CenterV);

    DBG_COLOR(0xFF0);          /* yellow = pass 2 */
    RenderShearPass2(D);

    Params.Chunky     = RotoChunky;
    Params.RowPtr     = RotoRowPtr[Buffer];
    Params.PairExpand = (const UBYTE*)&PairExpand;

    DBG_COLOR(0x0F0);          /* green = final chunky-to-bitplane pack */
    DrawRotoBodyAsm(&Params);
    DBG_COLOR(0x000);

    AnglePhase += 2;
    ZoomPhase  += ROTO_ZOOM_SPEED;
    ++MovePhaseX;
    MovePhaseY += 2;
}

void Cleanup_RotoZoomer(void)
{
    FreeMem(RotoChunky, RotoChunkySize);
    RotoChunky = NULL;
    RotoChunkySize = 0;

    FreeMem(ShearStage1, ShearStage1Size);
    ShearStage1 = NULL;
    ShearStage1Size = 0;

    FreeMem(TextureChunky, TextureSetSize);
    TextureChunky = NULL;
    TextureChunkySize = 0;
    TextureSetSize = 0;
    TextureRot[0] = NULL;
    TextureRot[1] = NULL;
    TextureRot[2] = NULL;
    TextureRot[3] = NULL;

    FreeMem(DeltaTab, DeltaTabSize);
    DeltaTab = NULL;
    DeltaTabSize = 0;
}

// =====================================================================
// Copper list
// =====================================================================

static UWORD *CopperList     = NULL;
static ULONG  CopperListSize = 0;

static UWORD BPLPTH_Idx[NUMBEROFBITPLANES];
static UWORD BPLPTL_Idx[NUMBEROFBITPLANES];

// Fixed header:
// DIWSTRT+DIWSTOP+DDFSTRT+DDFSTOP+BPLCON0+BPLCON1+BPL1MOD+BPL2MOD = 16 words
// 5 bitplane pointers = 20 words
// 32 colors = 64 words
// 192 visible lines * (WAIT + BPL1MOD + BPL2MOD) = ROTO_DISPLAY_HEIGHT * 6 words
// Moving the window lower crosses beam line 255 once, so one wrap WAIT pair is needed.
// END = 2 words
#define COPPER_EXTRA_WAIT_WORDS  (((ROTO_VPOS_START + ROTO_DISPLAY_HEIGHT) > 256) ? 2 : 0)
#define COPPERWORDS (16 + (NUMBEROFBITPLANES * 4) + (SCREEN_COLORS * 2) + (ROTO_DISPLAY_HEIGHT * 6) + COPPER_EXTRA_WAIT_WORDS + 2)

void Init_CopperList(void)
{
    CopperListSize = COPPERWORDS * sizeof(UWORD);
    CopperList = (UWORD*)AllocMem(CopperListSize, MEMF_CHIP | MEMF_CLEAR);

    UWORD Index = 0;

    CopperList[Index++] = 0x8E;
    CopperList[Index++] = ROTO_DIWSTRT;

    CopperList[Index++] = 0x90;
    CopperList[Index++] = ROTO_DIWSTOP;

    CopperList[Index++] = 0x92;
    CopperList[Index++] = ROTO_DDFSTRT;

    CopperList[Index++] = 0x94;
    CopperList[Index++] = ROTO_DDFSTOP;

    CopperList[Index++] = 0x100;
    CopperList[Index++] = 0x5200;

    CopperList[Index++] = 0x102;
    CopperList[Index++] = 0x0000;

    CopperList[Index++] = 0x108;
    CopperList[Index++] = ROTO_REPEAT_MOD;
    CopperList[Index++] = 0x10A;
    CopperList[Index++] = ROTO_REPEAT_MOD;

    for (UWORD p = 0; p < NUMBEROFBITPLANES; ++p)
    {
        CopperList[Index++] = (UWORD)(0x0E0u + (p * 4u));
        BPLPTH_Idx[p] = Index;
        CopperList[Index++] = 0x0000;

        CopperList[Index++] = (UWORD)(0x0E2u + (p * 4u));
        BPLPTL_Idx[p] = Index;
        CopperList[Index++] = 0x0000;
    }

    for (UWORD i = 0; i < SCREEN_COLORS; ++i)
    {
        CopperList[Index++] = (UWORD)(0x180u + (i * 2u));
        CopperList[Index++] = TexturePalette[i];
    }

    UWORD *CopperPtr = &CopperList[Index];

    for (UWORD y = 0; y < ROTO_DISPLAY_HEIGHT; ++y)
    {
        const UWORD Mod = ((y & 3u) == 3u) ? ROTO_ADVANCE_MOD : ROTO_REPEAT_MOD;
        const UWORD VPos = (UWORD)(ROTO_VPOS_START + y);

        if (VPos == 256)
        {
            *CopperPtr++ = 0xFFDF;
            *CopperPtr++ = 0xFFFE;
        }

        *CopperPtr++ = (UWORD)(((VPos & 0xFFu) << 8) | 0x07u);
        *CopperPtr++ = 0xFFFE;

        *CopperPtr++ = 0x108;
        *CopperPtr++ = Mod;
        *CopperPtr++ = 0x10A;
        *CopperPtr++ = Mod;
    }

    Index = (UWORD)(CopperPtr - CopperList);

    CopperList[Index++] = 0xFFFF;
    CopperList[Index++] = 0xFFFE;

    *COP1LC = (ULONG)CopperList;
}

void Update_BitplanePointers(UBYTE Buffer)
{
    ULONG Ptr = (ULONG)ScreenBitmap[Buffer]->Planes[0] + (ULONG)ROTO_START_BYTE;

    CopperList[BPLPTH_Idx[0]] = (UWORD)(Ptr >> 16);
    CopperList[BPLPTL_Idx[0]] = (UWORD)(Ptr & 0xFFFFu);

    Ptr += BYTESPERROW;
    CopperList[BPLPTH_Idx[1]] = (UWORD)(Ptr >> 16);
    CopperList[BPLPTL_Idx[1]] = (UWORD)(Ptr & 0xFFFFu);

    Ptr += BYTESPERROW;
    CopperList[BPLPTH_Idx[2]] = (UWORD)(Ptr >> 16);
    CopperList[BPLPTL_Idx[2]] = (UWORD)(Ptr & 0xFFFFu);

    Ptr += BYTESPERROW;
    CopperList[BPLPTH_Idx[3]] = (UWORD)(Ptr >> 16);
    CopperList[BPLPTL_Idx[3]] = (UWORD)(Ptr & 0xFFFFu);

    Ptr += BYTESPERROW;
    CopperList[BPLPTH_Idx[4]] = (UWORD)(Ptr >> 16);
    CopperList[BPLPTL_Idx[4]] = (UWORD)(Ptr & 0xFFFFu);
}

// =====================================================================
// Cleanup & Main
// =====================================================================

void Cleanup_All(void)
{
    Cleanup_RotoZoomer();

    FreeMem(CopperList, CopperListSize);
    CopperList = NULL;

    lwmf_CleanupScreenBitmaps();
    lwmf_CleanupAll();
}

int main(void)
{
    lwmf_LoadGraphicsLib();
    lwmf_InitScreenBitmaps();
    Init_RotoZoomer();
    Init_CopperList();

    lwmf_TakeOverOS();

    UBYTE CurrentBuffer = 1;
    Update_BitplanePointers(0);

    while (*CIAA_PRA & 0x40)
    {
        Draw_RotoZoomer(CurrentBuffer);

        DBG_COLOR(0x00F);
        lwmf_WaitVertBlank();
        DBG_COLOR(0x000);

        Update_BitplanePointers(CurrentBuffer);
        CurrentBuffer ^= 1;
    }

    Cleanup_All();
    return 0;
}
