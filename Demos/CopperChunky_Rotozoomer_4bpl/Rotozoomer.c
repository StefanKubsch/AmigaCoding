//**********************************************************************
//* 4x4 Copper Chunky Rotozoomer                                       *
//* 4 Bitplanes, 16 colors, 48 columns                                 *
//* Amiga 500 OCS                                                      *
//*                                                                    *
//* (C) 2020-2026 by Stefan Kubsch/Deep4                               *
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

typedef struct RotoRowPlanes
{
	UBYTE *P0;
	UBYTE *P1;
	UBYTE *P2;
	UBYTE *P3;
} RotoRowPlanes;

typedef struct RotoAsmParams
{
	const UBYTE                *Texture;
	const struct RotoRowPlanes *RowPtr;
	const UBYTE                *PairExpand;
	WORD                        RowU;
	WORD                        RowV;
	WORD                        DuDx;
	WORD                        DvDx;
	WORD                        DuDy;
	WORD                        DvDy;
} RotoAsmParams;

extern void DrawRotoBodyAsm(__reg("a0") const struct RotoAsmParams *Params);

// =====================================================================
// Effect constants
// =====================================================================

#define TEXTURE_FILENAME         "gfx/128x128_4bpl_2.iff"
#define TEXTURE_SOURCE_WIDTH     128
#define TEXTURE_SOURCE_HEIGHT    128

#define TEXTURE_WIDTH            256
#define TEXTURE_HEIGHT           256
#define TEXTURE_SAMPLE_BIAS      ((ULONG)TEXTURE_WIDTH * (ULONG)TEXTURE_SOURCE_HEIGHT)   /* 32768 */

#define SCREEN_COLORS            16
#define TEXTURE_COLOR_BASE       0

// Base zoom
#define ROTO_ZOOM_BASE           384
#define ROTO_ZOOM_AMPLITUDE      128
#define ROTO_ZOOM_SPEED          1

#define CHUNKY_PIXEL_SIZE        4
#define ROTO_COLUMNS             48
#define ROTO_ROWS                48
#define ROTO_PAIR_COUNT          (ROTO_COLUMNS / 2)
#define ROTO_DISPLAY_WIDTH       (ROTO_COLUMNS * CHUNKY_PIXEL_SIZE)
#define ROTO_DISPLAY_HEIGHT      (ROTO_ROWS * CHUNKY_PIXEL_SIZE)

#define ROTO_START_X             ((((SCREENWIDTH - ROTO_DISPLAY_WIDTH) >> 1)) & ~15)
#define ROTO_START_BYTE          (ROTO_START_X >> 3)

#define INTERLEAVED_STRIDE       (BYTESPERROW * NUMBEROFBITPLANES)
#define INTERLEAVEDMOD           (BYTESPERROW * (NUMBEROFBITPLANES - 1))

#define ROTO_FETCH_WORDS         (ROTO_DISPLAY_WIDTH / 16)
#define ROTO_FETCH_BYTES         (ROTO_DISPLAY_WIDTH / 8)
#define ROTO_REPEAT_MOD          ((UWORD)(-(WORD)ROTO_FETCH_BYTES))
#define ROTO_ADVANCE_MOD         ((UWORD)(INTERLEAVED_STRIDE - ROTO_FETCH_BYTES))

#define VPOS_OFFSET              0x2C

#define ROTO_VPOS_START          (VPOS_OFFSET + ((SCREENHEIGHT - ROTO_DISPLAY_HEIGHT) / 2))
#define ROTO_VPOS_STOP           (ROTO_VPOS_START + ROTO_DISPLAY_HEIGHT)
#define ROTO_DIWSTRT             (UWORD)(((ROTO_VPOS_START & 0xFFu) << 8) | 0x00C1u)
#define ROTO_DIWSTOP             (UWORD)(((ROTO_VPOS_STOP  & 0xFFu) << 8) | 0x0081u)
#define ROTO_DDFSTRT             0x0058
#define ROTO_DDFSTOP             0x00B0

typedef struct
{
	WORD DuDx;
	WORD DvDx;
	WORD DuDy;
	WORD DvDy;
} RotoDelta;

#define ROTO_HALF_COLUMNS   (ROTO_COLUMNS / 2)
#define ROTO_HALF_ROWS      (ROTO_ROWS / 2)
#define ROTO_ZOOM_STEPS     32

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
static const UBYTE *TextureSampleBase = NULL;
static ULONG TextureChunkySize = 0;

static UWORD TexturePalette[SCREEN_COLORS];
static UBYTE TextureColorBase = 0;

#define PAIR_EXPAND_STRIDE       256u
#define PAIR_EXPAND_WORD_BYTES   (PAIR_EXPAND_STRIDE * sizeof(UWORD))
#define PAIR_EXPAND_PLANE01_OFF  0u
#define PAIR_EXPAND_PLANE23_OFF  (PAIR_EXPAND_PLANE01_OFF + PAIR_EXPAND_WORD_BYTES)
#define PAIR_EXPAND_TOTAL_BYTES  (PAIR_EXPAND_PLANE23_OFF + PAIR_EXPAND_WORD_BYTES)

#define PAIR2IDX_STRIDE        65536ul
#define EXPAND4PIX_STRIDE      256u
#define PE_EXPAND4PIX_OFFSET   (PAIR2IDX_STRIDE * sizeof(UWORD))

typedef struct PairExpandSet
{
	/*
	 * Pair2Idx[key], with:
	 *   key low  byte = pair1 = c0 | (c1 << 4)
	 *   key high byte = pair2 = c2 | (c3 << 4)
	 *
	 * Stored value:
	 *   low  byte = idx01  (bits 0/1 of all 4 pixels)
	 *   high byte = idx23  (bits 2/3 of all 4 pixels, shifted down)
	 */
	UWORD Pair2Idx[PAIR2IDX_STRIDE];

	/*
	 * Expand4Pix[idx]:
	 *   idx contains 4 pixels with 2 bits each:
	 *     p0 in bits 1:0
	 *     p1 in bits 3:2
	 *     p2 in bits 5:4
	 *     p3 in bits 7:6
	 *
	 * Layout in ULONG:
	 *   high word = high plane word
	 *   low  word = low  plane word
	 *
	 * For idx01:
	 *   high word = plane1, low word = plane0
	 *
	 * For idx23:
	 *   high word = plane3, low word = plane2
	 */
	ULONG Expand4Pix[EXPAND4PIX_STRIDE];
} PairExpandSet;

static PairExpandSet *PairExpand = NULL;
static ULONG PairExpandSize = 0;

static UBYTE AnglePhase = 0;
static UBYTE ZoomPhase = 0;
static UBYTE MovePhaseX = 0;
static UBYTE MovePhaseY = 64;

// =====================================================================
// Texture loading and precomputation
// =====================================================================

static void BuildPairExpandTable(void)
{
	//
	// Pair2Idx:
	// Combine two already-sampled packed pairs directly into the two
	// 8-bit 4-pixel indices needed by Expand4Pix.
	///
	for (UWORD pair1 = 0; pair1 < 256u; ++pair1)
	{
		const UBYTE c0 = (UBYTE)(pair1 & 0x0Fu);
		const UBYTE c1 = (UBYTE)(pair1 >> 4u);

		const UBYTE idx01_lo = (UBYTE)((c0 & 0x03u) | ((c1 & 0x03u) << 2u));
		const UBYTE idx23_lo = (UBYTE)(((c0 >> 2u) & 0x03u) | (((c1 >> 2u) & 0x03u) << 2u));

		for (UWORD pair2 = 0; pair2 < 256u; ++pair2)
		{
			const UBYTE c2 = (UBYTE)(pair2 & 0x0Fu);
			const UBYTE c3 = (UBYTE)(pair2 >> 4u);

			const UBYTE idx01_hi = (UBYTE)((c2 & 0x03u) | ((c3 & 0x03u) << 2u));
			const UBYTE idx23_hi = (UBYTE)(((c2 >> 2u) & 0x03u) | (((c3 >> 2u) & 0x03u) << 2u));

			const UBYTE idx01 = (UBYTE)(idx01_lo | (idx01_hi << 4u));
			const UBYTE idx23 = (UBYTE)(idx23_lo | (idx23_hi << 4u));

			const UWORD key = (UWORD)(pair2 | (pair1 << 8u));

			PairExpand->Pair2Idx[key] = (UWORD)(((UWORD)idx23 << 8) | (UWORD)idx01);
		}
	}

	//
	// Expand 4 pixels with 2 bits each into two plane words.
	//
	for (UWORD idx = 0; idx < EXPAND4PIX_STRIDE; ++idx)
	{
		const UBYTE p0 = (UBYTE)( idx        & 0x03u);
		const UBYTE p1 = (UBYTE)((idx >> 2u) & 0x03u);
		const UBYTE p2 = (UBYTE)((idx >> 4u) & 0x03u);
		const UBYTE p3 = (UBYTE)((idx >> 6u) & 0x03u);

		const UBYTE lo_b0 = (UBYTE)(((p0 & 0x01u) ? 0xF0u : 0x00u) | ((p1 & 0x01u) ? 0x0Fu : 0x00u));
		const UBYTE lo_b1 = (UBYTE)(((p2 & 0x01u) ? 0xF0u : 0x00u) | ((p3 & 0x01u) ? 0x0Fu : 0x00u));

		const UBYTE hi_b0 = (UBYTE)(((p0 & 0x02u) ? 0xF0u : 0x00u) | ((p1 & 0x02u) ? 0x0Fu : 0x00u));
		const UBYTE hi_b1 = (UBYTE)(((p2 & 0x02u) ? 0xF0u : 0x00u) | ((p3 & 0x02u) ? 0x0Fu : 0x00u));

		const UWORD lo_word = (UWORD)(((UWORD)lo_b0 << 8) | (UWORD)lo_b1);
		const UWORD hi_word = (UWORD)(((UWORD)hi_b0 << 8) | (UWORD)hi_b1);

		PairExpand->Expand4Pix[idx] = ((ULONG)hi_word << 16) | (ULONG)lo_word;
	}
}

static void BuildChunkyTextureFromBitmap(struct lwmf_Image *RotoBitmap)
{
	const UBYTE PlaneCount = RotoBitmap->Image.Depth;
	const UWORD BytesPerRow = RotoBitmap->Image.BytesPerRow;
	const UWORD ColorCount = (UWORD)RotoBitmap->NumberOfColors;

	TextureChunkySize = (ULONG)TEXTURE_WIDTH * (ULONG)TEXTURE_HEIGHT;
	TextureChunky = (UBYTE*)lwmf_AllocCpuMem(TextureChunkySize, MEMF_CLEAR);

	TextureSampleBase = NULL;

	for (UWORD i = 0; i < SCREEN_COLORS; ++i)
	{
		TexturePalette[i] = 0x000u;
	}

	TextureColorBase = 0u;

	if (RotoBitmap->CRegs)
	{
		for (UWORD i = 0; i < ColorCount; ++i)
		{
			TexturePalette[i] = (UWORD)(RotoBitmap->CRegs[i] & 0x0FFFu);
		}
	}
	else
	{
		for (UWORD i = 0; i < ColorCount; ++i)
		{
			const UWORD V = (UWORD)((i * 15u) / ((ColorCount > 1u) ? (ColorCount - 1u) : 1u));
			TexturePalette[i] = (UWORD)((V << 8) | (V << 4) | V);
		}
	}

	/*
	 * Internal texture layout is 256x256.
	 *
	 * We duplicate each source row horizontally, so (U >> 8) remains a
	 * direct 0..255 texel X coordinate.
	 *
	 * Additionally, we duplicate the 128 source rows vertically into both halves
	 * of the 256-line texture and use a sample base pointer at +32768 bytes
	 * (middle of the buffer).
	 *
	 * That way, the ASM hotloop can use:
	 *     texIndex = (V & $FF00) + (U >> 8)
	 * and access it via signed 16-bit indexed addressing:
	 *
	 *   V high byte 00..7F -> positive offsets from TextureSampleBase
	 *   V high byte 80..FF -> negative offsets from TextureSampleBase
	 *
	 * Rows 128..255 are duplicates of rows 0..127, so this is equivalent to
	 * the old vertical wrap, just cheaper in the hotloop.
	 */
	for (UWORD y = 0; y < TEXTURE_SOURCE_HEIGHT; ++y)
	{
		UBYTE *DstNeg = TextureChunky + ((ULONG)y * (ULONG)TEXTURE_WIDTH);
		UBYTE *DstPos = TextureChunky + TEXTURE_SAMPLE_BIAS + ((ULONG)y * (ULONG)TEXTURE_WIDTH);

		for (UWORD x = 0; x < TEXTURE_SOURCE_WIDTH; ++x)
		{
			const UBYTE Mask = (UBYTE)(1u << (7u - (x & 7u)));
			const UWORD ByteOffset = (UWORD)(x >> 3u);
			UBYTE Index = 0;

			for (UBYTE p = 0; p < 4u; ++p)
			{
				const UBYTE *Plane = (const UBYTE*)RotoBitmap->Image.Planes[p];

				if (Plane[(ULONG)y * (ULONG)BytesPerRow + ByteOffset] & Mask)
				{
					Index |= (UBYTE)(1u << p);
				}
			}

			Index = (UBYTE)(Index + TextureColorBase);

			// first half: rows used by negative signed offsets
			DstNeg[x] = Index;
			DstNeg[x + TEXTURE_SOURCE_WIDTH] = Index;

			// second half: rows used by positive signed offsets
			DstPos[x] = Index;
			DstPos[x + TEXTURE_SOURCE_WIDTH] = Index;
		}
	}

	TextureSampleBase = TextureChunky + TEXTURE_SAMPLE_BIAS;
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
	for (UWORD a = 0; a < 256; ++a)
	{
		const WORD SinV = (WORD)SinTab256[a] - 32;
		const WORD CosV = (WORD)SinTab256[(UBYTE)(a + 64u)] - 32;

		for (UWORD z = 0; z < ROTO_ZOOM_STEPS; ++z)
		{
			const WORD ZoomMod = (WORD)(((WORD)z << 1) - 32);
			const WORD Zoom = (WORD)(ROTO_ZOOM_BASE + ((ZoomMod * ROTO_ZOOM_AMPLITUDE) >> 5));

			const WORD Ux = (WORD)(((LONG)CosV * (LONG)Zoom) >> 5);
			const WORD Vx = (WORD)(((LONG)SinV * (LONG)Zoom) >> 5);

			RotoDelta *D = &DeltaTab[a * ROTO_ZOOM_STEPS + z];

			D->DuDx = Ux;
			D->DvDx = Vx;
			D->DuDy = (WORD)(-Vx);
			D->DvDy = Ux;
		}
	}
}

static struct RotoRowPlanes RotoRowPtr[2][ROTO_ROWS];

static void BuildRowPointerTable(void)
{
	for (UBYTE Buffer = 0; Buffer < 2u; ++Buffer)
	{
		UBYTE *Base = (UBYTE*)ScreenBitmap[Buffer]->Planes[0];

		for (UWORD y = 0; y < ROTO_ROWS; ++y)
		{
			UBYTE *RowBase = Base + ((ULONG)y * INTERLEAVED_STRIDE) + ROTO_START_BYTE;

			RotoRowPtr[Buffer][y].P0 = RowBase + (BYTESPERROW * 0);
			RotoRowPtr[Buffer][y].P1 = RowBase + (BYTESPERROW * 1);
			RotoRowPtr[Buffer][y].P2 = RowBase + (BYTESPERROW * 2);
			RotoRowPtr[Buffer][y].P3 = RowBase + (BYTESPERROW * 3);
		}
	}
}

void Cleanup_RotoZoomer(void)
{
	FreeMem(TextureChunky, TextureChunkySize);
	TextureChunky = NULL;
	TextureSampleBase = NULL;
	TextureChunkySize = 0;
	FreeMem(PairExpand, PairExpandSize);
	PairExpand = NULL;
	PairExpandSize = 0;
	FreeMem(DeltaTab, DeltaTabSize);
	DeltaTab = NULL;
	DeltaTabSize = 0;
}

void Init_RotoZoomer(void)
{
	struct lwmf_Image *RotoBitmap;

	RotoBitmap = lwmf_LoadImage(TEXTURE_FILENAME);

	BuildChunkyTextureFromBitmap(RotoBitmap);

	lwmf_DeleteImage(RotoBitmap);

	DeltaTabSize = sizeof(RotoDelta) * 256u * ROTO_ZOOM_STEPS;
	DeltaTab = (RotoDelta*)lwmf_AllocCpuMem(DeltaTabSize, MEMF_CLEAR);

	PairExpandSize = (ULONG)sizeof(PairExpandSet);
	PairExpand = (PairExpandSet*)lwmf_AllocCpuMem(PairExpandSize, MEMF_CLEAR);

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
	const RotoDelta *D = &DeltaTab[(AnglePhase * ROTO_ZOOM_STEPS) + ZoomIndex];

	const WORD CenterU = MoveTab[MovePhaseX];
	const WORD CenterV = MoveTab[MovePhaseY];

	Params.Texture    = TextureSampleBase;
	Params.RowPtr     = RotoRowPtr[Buffer];
	Params.PairExpand = (const UBYTE*)PairExpand;

	Params.DuDx = D->DuDx;
	Params.DvDx = D->DvDx;
	Params.DuDy = D->DuDy;
	Params.DvDy = D->DvDy;

	Params.RowU = (WORD)(CenterU - (ROTO_HALF_COLUMNS * D->DuDx) - (ROTO_HALF_ROWS * D->DuDy));
	Params.RowV = (WORD)(CenterV - (ROTO_HALF_COLUMNS * D->DvDx) - (ROTO_HALF_ROWS * D->DvDy));

	DBG_COLOR(0xF00);
	DrawRotoBodyAsm(&Params);
	DBG_COLOR(0x000);

	AnglePhase += 2;
	ZoomPhase  += ROTO_ZOOM_SPEED;
	++MovePhaseX;
	MovePhaseY += 2;
}

// =====================================================================
// Copper list
// =====================================================================

static UWORD *CopperList     = NULL;
static ULONG  CopperListSize = 0;

static UWORD BPLPTH_Idx[NUMBEROFBITPLANES];
static UWORD BPLPTL_Idx[NUMBEROFBITPLANES];

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
	CopperList[Index++] = 0x4200;

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

		DBG_COLOR(0x0F0);
		lwmf_WaitVertBlank();
		DBG_COLOR(0x000);

		Update_BitplanePointers(CurrentBuffer);
		CurrentBuffer ^= 1;
	}

	Cleanup_All();
	return 0;
}