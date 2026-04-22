//**********************************************************************
//* 4x4 Copper Chunky Rotozoomer                                       *
//* 4 Bitplanes, 16 colors, 48 columns                                 *
//* Amiga 500 OCS                                                      *
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

// Enable (set to 1) for debugging
// When enabled, timing/load will be displayed via COLOR00 changes.
#define DEBUG 			0

#if DEBUG
	#define DBG_COLOR(c) (*COLOR00 = (c))
#else
	#define DBG_COLOR(c) ((void)0)
#endif

typedef struct RotoAsmParams
{
	const UBYTE *Texture;
	UBYTE        *Dest;
	const UBYTE *PairExpand;
	WORD         RowU;
	WORD         RowV;
	WORD         DuDx;
	WORD         DvDx;
	WORD         DuDy;
	WORD         DvDy;
} RotoAsmParams;

extern void DrawRotoBodyAsm(__reg("a0") const struct RotoAsmParams *Params);

// =====================================================================
// Effect constants
// =====================================================================

#define TEXTURE_FILENAME         "gfx/128x128_4bpl_2.iff"
#define TEXTURE_SOURCE_WIDTH     128
#define TEXTURE_SOURCE_HEIGHT    128
#define TEXTURE_WIDTH            256
#define TEXTURE_HEIGHT           TEXTURE_SOURCE_HEIGHT

#define ROTO_BITPLANES           4
#define SCREEN_COLORS            16
#define TEXTURE_COLOR_BASE       1

// Base zoom
// Larger value  = further out  (more of the texture visible)
// Smaller value = further in   (less of the texture visible)
#define ROTO_ZOOM_BASE           384
// Zoom animation amplitude
#define ROTO_ZOOM_AMPLITUDE      128
#define ROTO_ZOOM_SPEED          1

#define CHUNKY_PIXEL_SIZE        4
#define ROTO_COLUMNS             48
#define ROTO_ROWS                48
#define ROTO_PAIR_COUNT          (ROTO_COLUMNS / 2)
#define ROTO_DISPLAY_WIDTH       (ROTO_COLUMNS * CHUNKY_PIXEL_SIZE)
#define ROTO_DISPLAY_HEIGHT      (ROTO_ROWS * CHUNKY_PIXEL_SIZE)

// Byte aligned on purpose, so each pair of 4x pixels maps to one byte.
#define ROTO_START_X             ((((SCREENWIDTH - ROTO_DISPLAY_WIDTH) >> 1)) & ~7)
#define ROTO_START_BYTE          (ROTO_START_X >> 3)

#define INTERLEAVED_STRIDE       (BYTESPERROW * ROTO_BITPLANES)
#define INTERLEAVEDMOD           (BYTESPERROW * (ROTO_BITPLANES - 1))

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

// Precalculated delta table stores only the independent matrix terms.
// The animation advances AnglePhase by 2 every frame, so only the 128 even
// angle phases are ever used. For a pure rotation matrix the vertical row step
// can be reconstructed from the horizontal step:
//   DuDy = -DvDx
//   DvDy =  DuDx
// Therefore the table only stores DuDx and DvDx.
typedef struct
{
	WORD DuDx;
	WORD DvDx;
} RotoDelta;

#define ROTO_HALF_COLUMNS      (ROTO_COLUMNS / 2)
#define ROTO_HALF_ROWS         (ROTO_ROWS / 2)
#define ROTO_ZOOM_STEPS        32
#define ROTO_ANGLE_PHASE_STEP   2
#define ROTO_ANGLE_STEPS        (256 / ROTO_ANGLE_PHASE_STEP)

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

static UBYTE *TextureChunky = NULL;
static ULONG TextureChunkySize = 0;
static UWORD TexturePalette[SCREEN_COLORS];
static UBYTE TextureColorBase = 0;

#define PAIR_EXPAND_STRIDE       256u
#define PAIR_EXPAND_WORD_BYTES   (PAIR_EXPAND_STRIDE * sizeof(UWORD))
#define PAIR_EXPAND_PLANE01_OFF  0u
#define PAIR_EXPAND_PLANE23_OFF  (PAIR_EXPAND_PLANE01_OFF + PAIR_EXPAND_WORD_BYTES)
#define PAIR_EXPAND_TOTAL_BYTES  (PAIR_EXPAND_PLANE23_OFF + PAIR_EXPAND_WORD_BYTES)

typedef struct PairExpandSet
{
	UWORD Plane01[PAIR_EXPAND_STRIDE];
	UWORD Plane23[PAIR_EXPAND_STRIDE];
} PairExpandSet;

static PairExpandSet PairExpand;

static UBYTE AnglePhase = 0;
static UBYTE ZoomPhase = 0;
static UBYTE MovePhaseX = 0;
static UBYTE MovePhaseY = 64;


// =====================================================================
// Texture loading and precomputation
// =====================================================================

static void BuildPairExpandTable(void)
{
	// Build a 2-read expansion layout for all possible packed 2-pixel
	// combinations.
	//
	// Each packed value is:
	//   packed = c0 | (c1 << 4)
	// with c0/c1 being 4-bit chunky color indices.
	//
	// We store:
	//   - Plane01[packed] as a UWORD holding plane 0 in the low byte and
	//     plane 1 in the high byte
	//   - Plane23[packed] as a UWORD holding plane 2 in the low byte and
	//     plane 3 in the high byte
	//
	// Total size becomes 1024 bytes:
	//   256 * 2 + 256 * 2 = 1024
	//
	// This lets the ASM hotloop fetch all four output bytes with only
	// two table reads per packed pair.

	for (UWORD packed = 0; packed < PAIR_EXPAND_STRIDE; ++packed)
	{
		const UBYTE c0 = (UBYTE)(packed & 15u);
		const UBYTE c1 = (UBYTE)(packed >> 4u);

		const UBYTE b0 = (UBYTE)(((c0 & 0x01u) ? 0xF0u : 0x00u) | ((c1 & 0x01u) ? 0x0Fu : 0x00u));
		const UBYTE b1 = (UBYTE)(((c0 & 0x02u) ? 0xF0u : 0x00u) | ((c1 & 0x02u) ? 0x0Fu : 0x00u));
		const UBYTE b2 = (UBYTE)(((c0 & 0x04u) ? 0xF0u : 0x00u) | ((c1 & 0x04u) ? 0x0Fu : 0x00u));
		const UBYTE b3 = (UBYTE)(((c0 & 0x08u) ? 0xF0u : 0x00u) | ((c1 & 0x08u) ? 0x0Fu : 0x00u));

		PairExpand.Plane01[packed] = (UWORD)(((UWORD)b1 << 8) | (UWORD)b0);
		PairExpand.Plane23[packed] = (UWORD)(((UWORD)b3 << 8) | (UWORD)b2);
	}
}

static void BuildChunkyTextureFromBitmap(struct lwmf_Image *RotoBitmap)
{
	const UBYTE PlaneCount = RotoBitmap->Image.Depth;
	const UWORD BytesPerRow = RotoBitmap->Image.BytesPerRow;
	const UWORD ColorCount = (UWORD)RotoBitmap->NumberOfColors;

	TextureChunkySize = (ULONG)TEXTURE_WIDTH * (ULONG)TEXTURE_HEIGHT;
	TextureChunky = (UBYTE*)lwmf_AllocCpuMem(TextureChunkySize, MEMF_CLEAR);

	for (UWORD i = 0; i < SCREEN_COLORS; ++i)
	{
		TexturePalette[i] = 0x000u;
	}

	// If the texture uses fewer than 16 colors, reserve COLOR00 for a black background
	// and shift the texture palette by +1. If it already uses all 16 colors, keep the
	// palette unshifted; otherwise color index 16 would overflow the 4-bit pixel format.
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

	/*
	 * Internal texture layout is 256x128 although the source image is 128x128.
	 * Each source row is duplicated horizontally into the second 128-byte half.
	 * This keeps the sampled image identical while allowing the ASM hotloop to
	 * use (U >> 8) directly as a 0..255 texel X coordinate.
	 */
	for (UWORD y = 0; y < TEXTURE_SOURCE_HEIGHT; ++y)
	{
		UBYTE *Dst = TextureChunky + (ULONG)y * (ULONG)TEXTURE_WIDTH;

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

			Index = (UBYTE)(Index + TextureColorBase);
			Dst[x] = Index;
			Dst[x + TEXTURE_SOURCE_WIDTH] = Index;
		}
	}
}

// =====================================================================
// Rotozoomer
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
	for (UWORD a = 0; a < ROTO_ANGLE_STEPS; ++a)
	{
		const UBYTE Angle = (UBYTE)(a * ROTO_ANGLE_PHASE_STEP);
		const WORD SinV = (WORD)SinTab256[Angle] - 32;
		const WORD CosV = (WORD)SinTab256[(UBYTE)(Angle + 64u)] - 32;

		for (UWORD z = 0; z < ROTO_ZOOM_STEPS; ++z)
		{
			const WORD ZoomMod = (WORD)(((WORD)z << 1) - 32);
			const WORD Zoom = (WORD)(ROTO_ZOOM_BASE + ((ZoomMod * ROTO_ZOOM_AMPLITUDE) >> 5));

			RotoDelta *D = &DeltaTab[a * ROTO_ZOOM_STEPS + z];

			D->DuDx = (WORD)(((LONG)CosV * (LONG)Zoom) >> 5);
			D->DvDx = (WORD)(((LONG)SinV * (LONG)Zoom) >> 5);
		}
	}
}


static void Init_RotoZoomer(void)
{
	struct lwmf_Image *RotoBitmap;

	RotoBitmap = lwmf_LoadImage(TEXTURE_FILENAME);

	DeltaTabSize = sizeof(RotoDelta) * ROTO_ANGLE_STEPS * ROTO_ZOOM_STEPS;
	DeltaTab = (RotoDelta*)lwmf_AllocCpuMem(DeltaTabSize, MEMF_CLEAR);

	BuildChunkyTextureFromBitmap(RotoBitmap);

	lwmf_DeleteImage(RotoBitmap);

	BuildPairExpandTable();
	BuildMoveTable();
	BuildDeltaTable();

	AnglePhase = 0;
	ZoomPhase  = 0;
	MovePhaseX = 0;
	MovePhaseY = 64;
}

static void Draw_RotoZoomer(UBYTE Buffer)
{
	RotoAsmParams Params;
	const UBYTE ZoomIndex = (UBYTE)(SinTab256[ZoomPhase] >> 1);
	const UBYTE AngleIndex = (UBYTE)(AnglePhase >> 1);
	const RotoDelta *D = &DeltaTab[((UWORD)AngleIndex * ROTO_ZOOM_STEPS) + ZoomIndex];
	const WORD DuDx = D->DuDx;
	const WORD DvDx = D->DvDx;
	const WORD DuDy = (WORD)(-DvDx);
	const WORD DvDy = DuDx;

	const WORD CenterU = MoveTab[MovePhaseX];
	const WORD CenterV = MoveTab[MovePhaseY];

	Params.Texture    = TextureChunky;
	Params.Dest       = (UBYTE*)ScreenBitmap[Buffer]->Planes[0] + (ULONG)ROTO_START_BYTE;
	Params.PairExpand = (const UBYTE*)&PairExpand;

	Params.DuDx = DuDx;
	Params.DvDx = DvDx;
	Params.DuDy = DuDy;
	Params.DvDy = DvDy;

	Params.RowU = (WORD)(CenterU - (ROTO_HALF_COLUMNS * DuDx) - (ROTO_HALF_ROWS * DuDy));
	Params.RowV = (WORD)(CenterV - (ROTO_HALF_COLUMNS * DvDx) - (ROTO_HALF_ROWS * DvDy));

	DBG_COLOR(0xF00);          /* red = hotloop */
	DrawRotoBodyAsm(&Params);
	DBG_COLOR(0x000);          /* end of hotloop bar */

	AnglePhase += 2;
	ZoomPhase  += ROTO_ZOOM_SPEED;
	++MovePhaseX;
	MovePhaseY += 2;
}

static void Cleanup_RotoZoomer(void)
{
	FreeMem(TextureChunky, TextureChunkySize);
	TextureChunky = NULL;
	TextureChunkySize = 0;
	FreeMem(DeltaTab, DeltaTabSize);
	DeltaTab = NULL;
	DeltaTabSize = 0;
}

// =====================================================================
// Copper list
// =====================================================================

static UWORD *CopperList     = NULL;
static ULONG  CopperListSize = 0;

static UWORD BPLPTH_Idx[ROTO_BITPLANES];
static UWORD BPLPTL_Idx[ROTO_BITPLANES];

// Fixed header:
// DIWSTRT+DIWSTOP+DDFSTRT+DDFSTOP+BPLCON0+BPLCON1+BPL1MOD+BPL2MOD = 16 words
// 4 bitplane pointers = 16 words
// 16 colors = 32 words
// 192 visible lines * (WAIT + BPL1MOD + BPL2MOD) = ROTO_DISPLAY_HEIGHT * 6 words
// Moving the window lower crosses beam line 255 once, so one wrap WAIT pair is needed.
// END = 2 words
#define COPPER_EXTRA_WAIT_WORDS  (((ROTO_VPOS_START + ROTO_DISPLAY_HEIGHT) > 256) ? 2 : 0)
#define COPPERWORDS (16 + (ROTO_BITPLANES * 4) + (SCREEN_COLORS * 2) + (ROTO_DISPLAY_HEIGHT * 6) + COPPER_EXTRA_WAIT_WORDS + 2)

static void Init_CopperList(void)
{
	CopperListSize = COPPERWORDS * sizeof(UWORD);
	CopperList = (UWORD*)AllocMem(CopperListSize, MEMF_CHIP | MEMF_CLEAR);

	UWORD Index = 0;

	// Centered 192-pixel lowres display window with 192 visible lines,
	// shifted downward inside the standard PAL 256-line playfield area.
	CopperList[Index++] = 0x8E;
	CopperList[Index++] = ROTO_DIWSTRT;

	CopperList[Index++] = 0x90;
	CopperList[Index++] = ROTO_DIWSTOP;

	// Narrow centered fetch window: 12 fetch words * 16 pixels = 192 pixels.
	CopperList[Index++] = 0x92;
	CopperList[Index++] = ROTO_DDFSTRT;

	CopperList[Index++] = 0x94;
	CopperList[Index++] = ROTO_DDFSTOP;

	// 4 bitplanes, color mode, lowres
	CopperList[Index++] = 0x100;
	CopperList[Index++] = 0x4200;

	// No horizontal bitplane shift
	CopperList[Index++] = 0x102;
	CopperList[Index++] = 0x0000;

	// Start with the repeat modulo for the narrow fetch width.
	CopperList[Index++] = 0x108;
	CopperList[Index++] = ROTO_REPEAT_MOD;
	CopperList[Index++] = 0x10A;
	CopperList[Index++] = ROTO_REPEAT_MOD;

	// Bitplane pointers (filled later for each backbuffer)
	for (UWORD p = 0; p < ROTO_BITPLANES; ++p)
	{
		CopperList[Index++] = (UWORD)(0x0E0u + (p * 4u));
		BPLPTH_Idx[p] = Index;
		CopperList[Index++] = 0x0000;

		CopperList[Index++] = (UWORD)(0x0E2u + (p * 4u));
		BPLPTL_Idx[p] = Index;
		CopperList[Index++] = 0x0000;
	}

	// Static palette copied from the texture. COLOR00 stays black only when the
	// texture uses fewer than 16 colors and could be shifted by +1 safely.
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

static void Update_BitplanePointers(UBYTE Buffer)
{
	ULONG Ptr = (ULONG)ScreenBitmap[Buffer]->Planes[0] + (ULONG)ROTO_START_BYTE;

	for (UWORD p = 0; p < ROTO_BITPLANES; ++p)
	{
		CopperList[BPLPTH_Idx[p]] = (UWORD)(Ptr >> 16);
		CopperList[BPLPTL_Idx[p]] = (UWORD)(Ptr & 0xFFFFu);
		Ptr += BYTESPERROW;
	}
}

// =====================================================================
// Cleanup & Main
// =====================================================================

static void Cleanup_All(void)
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

		DBG_COLOR(0x0F0);
		lwmf_WaitVertBlank();
		DBG_COLOR(0x000);

		Update_BitplanePointers(CurrentBuffer);
		CurrentBuffer ^= 1;
	}

	Cleanup_All();
	return 0;
}
