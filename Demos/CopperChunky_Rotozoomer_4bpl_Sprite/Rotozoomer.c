//**********************************************************************
//* 4x4 Copper Chunky Rotozoomer - Sprite Assist Hybrid                *
//* 4 Bitplanes wings + 4 attached sprite pairs in the center          *
//* 16 colors, 48 logical columns, 192x192 display area                *
//* Amiga 500 OCS                                                      *
//*                                                                    *
//* Hybrid layout per logical row:                                     *
//*   4 blocks playfield  |  4 blocks attached sprites  |  4 blocks PF *
//*      64 pixels        |         64 pixels            |   64 pixels  *
//*                                                                    *
//* Based on the original project by Stefan Kubsch / Deep4             *
//**********************************************************************

#include "lwmf/lwmf.h"

// Enable (set to 1) for debugging.
// IMPORTANT for the sprite-assist hybrid:
// COLOR00 is visible in the centre span whenever the attached sprites output
// colour 0 (transparent) and fall through to playfield colour 0. Therefore
// timing visualisation via COLOR00 causes visible flicker / wrong colours in
// the sprite-assisted middle strip. Keep this disabled for normal runs.
#define DEBUG 0

#if DEBUG
	#define DBG_COLOR(c) (*COLOR00 = (c))
#else
	#define DBG_COLOR(c) ((void)0)
#endif

// Set to 1 to bypass the roto sampler for the centre span and emit a fixed
// attached-sprite test pattern. Useful to verify position, palette and attach
// mode independently from the roto math.
#define SPRITE_SELFTEST 0

typedef struct RotoRowPlanes
{
	UBYTE *P0;
	UBYTE *P1;
	UBYTE *P2;
	UBYTE *P3;
} RotoRowPlanes;

typedef struct RotoAsmParams
{
	const UBYTE *Texture;
	UBYTE       *PlayfieldBase;
	ULONG       *SpriteDataBase;
	const UBYTE *PairExpand;
	WORD         RowU;
	WORD         RowV;
	WORD         DuDx;
	WORD         DvDx;
	WORD         DuDy;
	WORD         DvDy;
} RotoAsmParams;

extern void DrawRotoHybridAsm(__reg("a0") const struct RotoAsmParams *Params);

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
#define SPRITE_COLORS            15
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
#define ROTO_VISIBLE_Y           ((SCREENHEIGHT - ROTO_DISPLAY_HEIGHT) / 2)

#define ROTO_FETCH_WORDS         (ROTO_DISPLAY_WIDTH / 16)
#define ROTO_FETCH_BYTES         (ROTO_DISPLAY_WIDTH / 8)
#define ROTO_BUFFER_PLANEBYTES   ROTO_FETCH_BYTES
#define ROTO_BUFFER_STRIDE       (ROTO_BUFFER_PLANEBYTES * NUMBEROFBITPLANES)
#define ROTO_REPEAT_MOD          ((UWORD)(-(WORD)ROTO_FETCH_BYTES))
#define ROTO_ADVANCE_MOD         ((UWORD)(ROTO_BUFFER_STRIDE - ROTO_FETCH_BYTES))

#define VPOS_OFFSET              0x2C

#define ROTO_VPOS_START          (VPOS_OFFSET + ROTO_VISIBLE_Y)
#define ROTO_VPOS_STOP           (ROTO_VPOS_START + ROTO_DISPLAY_HEIGHT)
#define ROTO_DIWSTRT             (UWORD)(((ROTO_VPOS_START & 0xFFu) << 8) | 0x00C1u)
#define ROTO_DIWSTOP             (UWORD)(((ROTO_VPOS_STOP  & 0xFFu) << 8) | 0x0081u)
#define ROTO_DDFSTRT             0x0058
#define ROTO_DDFSTOP             0x00B0

/*
 * Sprite X coordinates are not in playfield-relative 0..319 pixels.
 * They must be biased to the current display-window start.
 *
 * The classic "+64" rule only applies to the standard DIWSTRT HSTART=$81.
 * This project uses HSTART=$C1, so the correct bias here is 128 pixels.
 * Derive it from DIWSTRT instead of hardcoding 64.
 */
#define SPRITE_HSTART_BIAS       ((UWORD)(((ROTO_DIWSTRT & 0x00FFu) - 0x0041u)))

#define ROTO_SPAN_BLOCKS         4u
#define ROTO_LOGICAL_PIXELS_PER_SPAN (ROTO_SPAN_BLOCKS * 4u)
#define ROTO_WING_DISPLAY_WIDTH  64u
#define ROTO_CENTER_DISPLAY_WIDTH 64u
#define ROTO_CENTER_START_X      (ROTO_START_X + ROTO_WING_DISPLAY_WIDTH)
#define ROTO_RIGHT_START_X       (ROTO_CENTER_START_X + ROTO_CENTER_DISPLAY_WIDTH)
#define ROTO_LEFT_START_BYTE     0u
#define ROTO_CENTER_START_BYTE   (ROTO_WING_DISPLAY_WIDTH / 8u)
#define ROTO_RIGHT_START_BYTE    ((ROTO_WING_DISPLAY_WIDTH + ROTO_CENTER_DISPLAY_WIDTH) / 8u)
#define ROTO_CENTER_START_LOGICAL 16u
#define ROTO_RIGHT_START_LOGICAL  32u

#define SPRITE_PAIR_COUNT        4u
#define SPRITE_CHANNEL_COUNT     8u
#define SPRITE_DATA_HEIGHT       ROTO_DISPLAY_HEIGHT
#define SPRITE_CTRL_WORDS        2u
#define SPRITE_END_WORDS         2u
#define SPRITE_WORDS_PER_LINE    2u
#define SPRITE_WORDS_PER_CHANNEL (SPRITE_CTRL_WORDS + (SPRITE_DATA_HEIGHT * SPRITE_WORDS_PER_LINE) + SPRITE_END_WORDS)
#define SPRITE_BYTES_PER_CHANNEL (SPRITE_WORDS_PER_CHANNEL * sizeof(UWORD))
#define SPRITE_BYTES_PER_BUFFER  (SPRITE_CHANNEL_COUNT * SPRITE_BYTES_PER_CHANNEL)
#define SPRITE_TEMPLATE_WORDS_PER_BLOCK 4u
#define SPRITE_TEMPLATE_WORDS_PER_ROW (SPRITE_PAIR_COUNT * SPRITE_TEMPLATE_WORDS_PER_BLOCK)
#define SPRITE_TEMPLATE_BYTES_PER_BUFFER (ROTO_ROWS * SPRITE_TEMPLATE_WORDS_PER_ROW * sizeof(UWORD))

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

#define PAIR_SPLIT_STRIDE      256u
#define EXPAND4PIX_STRIDE      256u

typedef struct PairSplitEntry
{
	UWORD Lo;
	UWORD Hi;
} PairSplitEntry;

typedef struct PairExpandSet
{
	/*
	 * PairSplit[pair], pair = c0 | (c1 << 4)
	 *
	 *   Lo = low-nibble contribution:  [idx23_lo | idx01_lo]
	 *   Hi = high-nibble contribution: [idx23_hi | idx01_hi]
	 *
	 * Final packed index word for one 4-pixel block is:
	 *   packed = PairSplit[pair1].Lo | PairSplit[pair2].Hi
	 *
	 * Storing Lo and Hi interleaved keeps both lookups reachable through
	 * one 68000-safe indexed base with only a tiny displacement (0 / 2).
	 */
	PairSplitEntry PairSplit[PAIR_SPLIT_STRIDE];

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

#define SPRITE_LOGICAL_ROW_STRIDE_LONGS  ((ULONG)CHUNKY_PIXEL_SIZE)
#define SPRITE_CHANNEL_STRIDE_LONGS      ((ULONG)SPRITE_BYTES_PER_CHANNEL / sizeof(ULONG))
#define SPRITE_PAIR_STRIDE_LONGS         (SPRITE_CHANNEL_STRIDE_LONGS * 2u)

static ULONG *SpriteDataBase[2] = { NULL, NULL };
static UWORD *SpriteDMABuffer[2] = { NULL, NULL };
static UWORD *SpriteChannelPtr[2][SPRITE_CHANNEL_COUNT];

/* Forward declarations for Copper-managed sprite pointers. */
static UWORD *CopperList;
static UWORD SPRPTH_Idx[SPRITE_CHANNEL_COUNT];
static UWORD SPRPTL_Idx[SPRITE_CHANNEL_COUNT];

static BOOL OsTakenOver = FALSE;

// =====================================================================
// Local hardware register access
// =====================================================================

static volatile UWORD * const COPJMP1_REG = (volatile UWORD* const)0xDFF088;
static volatile UWORD * const DMACON_REG  = (volatile UWORD* const)0xDFF096;
static volatile ULONG * const VPOSR_REG  = (volatile ULONG* const)0xDFF004;

static void WaitNextVertBlankEdge(void)
{
	while ((*VPOSR_REG & 0x0001FF00ul) == (303ul << 8))
	{
	}

	while ((*VPOSR_REG & 0x0001FF00ul) != (303ul << 8))
	{
	}
}

static BOOL Init_RotoScreenBitmaps(void)
{
	const ULONG screenBytes = (ULONG)ROTO_BUFFER_STRIDE * (ULONG)ROTO_ROWS;

	for (UBYTE i = 0; i < 2u; ++i)
	{
		if (!(ScreenBitmapMem[i] = (UBYTE*)AllocMem(screenBytes, MEMF_CHIP | MEMF_CLEAR)))
		{
			return FALSE;
		}

		lwmf_InitBitMap(&ScreenBitmapStruct[i], NUMBEROFBITPLANES, ROTO_DISPLAY_WIDTH, ROTO_ROWS);
		ScreenBitmapStruct[i].BytesPerRow = (UWORD)ROTO_BUFFER_STRIDE;
		ScreenBitmapStruct[i].Rows = ROTO_ROWS;

		for (UBYTE p = 0; p < NUMBEROFBITPLANES; ++p)
		{
			ScreenBitmapStruct[i].Planes[p] = (PLANEPTR)(ScreenBitmapMem[i] + ((ULONG)p * ROTO_BUFFER_PLANEBYTES));
		}

		ScreenBitmap[i] = &ScreenBitmapStruct[i];
	}

	return TRUE;
}

static void Cleanup_RotoScreenBitmaps(void)
{
	const ULONG screenBytes = (ULONG)ROTO_BUFFER_STRIDE * (ULONG)ROTO_ROWS;

	for (UBYTE i = 0; i < 2u; ++i)
	{
		if (ScreenBitmapMem[i])
		{
			FreeMem(ScreenBitmapMem[i], screenBytes);
			ScreenBitmapMem[i] = NULL;
		}

		ScreenBitmap[i] = NULL;
	}
}


// =====================================================================
// Texture loading and precomputation
// =====================================================================

static APTR AllocCpuMem(ULONG Size, ULONG Flags)
{
	APTR Ptr = AllocMem(Size, MEMF_FAST | Flags);

	if (!Ptr)
	{
		Ptr = AllocMem(Size, MEMF_ANY | Flags);
	}

	return Ptr;
}

static void BuildPairExpandTable(void)
{
	/*
	 * pair1 contributes the low nibbles of idx01 / idx23,
	 * pair2 contributes the high nibbles.
	 */
	for (UWORD pair = 0; pair < PAIR_SPLIT_STRIDE; ++pair)
	{
		const UBYTE c0 = (UBYTE)(pair & 0x0Fu);
		const UBYTE c1 = (UBYTE)(pair >> 4u);

		const UBYTE idx01 = (UBYTE)((c0 & 0x03u) | ((c1 & 0x03u) << 2u));
		const UBYTE idx23 = (UBYTE)(((c0 >> 2u) & 0x03u) | (((c1 >> 2u) & 0x03u) << 2u));

		PairExpand->PairSplit[pair].Lo = (UWORD)(((UWORD)idx23 << 8) | (UWORD)idx01);
		PairExpand->PairSplit[pair].Hi = (UWORD)(((UWORD)idx23 << 12) | ((UWORD)idx01 << 4));
	}

	/*
	 * Expand 4 pixels with 2 bits each into two plane words.
	 */
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

static BOOL BuildChunkyTextureFromBitmap(struct lwmf_Image *RotoBitmap)
{
	const UBYTE PlaneCount = RotoBitmap->Image.Depth;
	const UWORD BytesPerRow = RotoBitmap->Image.BytesPerRow;
	const UWORD ColorCount = (UWORD)RotoBitmap->NumberOfColors;

	if (RotoBitmap->Width != TEXTURE_SOURCE_WIDTH ||
	    RotoBitmap->Height != TEXTURE_SOURCE_HEIGHT ||
	    PlaneCount != 4u ||
	    ColorCount == 0u ||
	    ColorCount > SCREEN_COLORS)
	{
		return FALSE;
	}

	TextureChunkySize = (ULONG)TEXTURE_WIDTH * (ULONG)TEXTURE_HEIGHT;
	TextureChunky = (UBYTE*)AllocCpuMem(TextureChunkySize, MEMF_CLEAR);

	if (!TextureChunky)
	{
		return FALSE;
	}

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
	 * We still duplicate each source row horizontally, so (U >> 8) remains a
	 * direct 0..255 texel X coordinate.
	 *
	 * Additionally, we duplicate the 128 source rows vertically into both halves
	 * of the 256-line texture and use a sample base pointer at +32768 bytes
	 * (middle of the buffer).
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

			/* first half: rows used by negative signed offsets */
			DstNeg[x] = Index;
			DstNeg[x + TEXTURE_SOURCE_WIDTH] = Index;

			/* second half: rows used by positive signed offsets */
			DstPos[x] = Index;
			DstPos[x + TEXTURE_SOURCE_WIDTH] = Index;
		}
	}

	TextureSampleBase = TextureChunky + TEXTURE_SAMPLE_BIAS;
	return TRUE;
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

static void BuildSpriteControlWords(UWORD visibleX, UWORD visibleY, UWORD height, BOOL attach, UWORD *posOut, UWORD *ctlOut)
{
	const UWORD hstart = (UWORD)(visibleX + SPRITE_HSTART_BIAS);
	const UWORD vstart = (UWORD)(visibleY + VPOS_OFFSET);
	const UWORD vstop  = (UWORD)(vstart + height);
	UWORD ctl = (UWORD)((vstop & 0x00FFu) << 8);

	if (attach)
	{
		ctl |= 0x0080u;
	}

	if (vstart & 0x0100u)
	{
		ctl |= 0x0004u;
	}

	if (vstop & 0x0100u)
	{
		ctl |= 0x0002u;
	}

	if (hstart & 0x0001u)
	{
		ctl |= 0x0001u;
	}

	*posOut = (UWORD)(((vstart & 0x00FFu) << 8) | ((hstart >> 1u) & 0x00FFu));
	*ctlOut = ctl;
}

static void BuildSpriteBuffers(void)
{
	for (UBYTE Buffer = 0; Buffer < 2u; ++Buffer)
	{
		SpriteDataBase[Buffer] = (ULONG*)(SpriteDMABuffer[Buffer] + SPRITE_CTRL_WORDS);

		for (UBYTE ch = 0; ch < SPRITE_CHANNEL_COUNT; ++ch)
		{
			UWORD *Channel = SpriteDMABuffer[Buffer] + ((ULONG)ch * SPRITE_WORDS_PER_CHANNEL);
			const UBYTE Pair = (UBYTE)(ch >> 1u);
			const UWORD PosX = (UWORD)(ROTO_CENTER_START_X + ((UWORD)Pair * 16u));
			UWORD Pos;
			UWORD Ctl;

			BuildSpriteControlWords(PosX, ROTO_VISIBLE_Y, SPRITE_DATA_HEIGHT, (BOOL)(ch & 1u), &Pos, &Ctl);

			Channel[0] = Pos;
			Channel[1] = Ctl;
			Channel[SPRITE_WORDS_PER_CHANNEL - 2u] = 0x0000u;
			Channel[SPRITE_WORDS_PER_CHANNEL - 1u] = 0x0000u;

			SpriteChannelPtr[Buffer][ch] = Channel;
		}
	}
}

static void UpdateSpritePointers(UBYTE Buffer)
{
	for (UBYTE ch = 0; ch < SPRITE_CHANNEL_COUNT; ++ch)
	{
		const ULONG Ptr = (ULONG)SpriteChannelPtr[Buffer][ch];

		/*
		 * Drive sprite pointers through the Copper list instead of writing the
		 * hardware registers directly every frame. This keeps all 8 sprite
		 * channels coherent at frame start and avoids even/odd pair skew in
		 * attached-sprite mode.
		 */
		CopperList[SPRPTH_Idx[ch]] = (UWORD)(Ptr >> 16);
		CopperList[SPRPTL_Idx[ch]] = (UWORD)(Ptr & 0xFFFFu);
	}
}

static void EnableSpriteDMA(void)
{
	*DMACON_REG = 0x8220u;
}

static void DisableSpriteDMA(void)
{
	*DMACON_REG = 0x0020u;
}

static void CommitSpritePointers(UBYTE Buffer)
{
	/*
	 * Sprite pointers are now emitted by the Copper at frame start. Updating the
	 * Copper list contents during vertical blank is sufficient; no per-frame DMA
	 * toggling is required here.
	 */
	UpdateSpritePointers(Buffer);
}

void Cleanup_RotoZoomer(void)
{
	for (UBYTE Buffer = 0; Buffer < 2u; ++Buffer)
	{
		if (SpriteDMABuffer[Buffer])
		{
			FreeMem(SpriteDMABuffer[Buffer], SPRITE_BYTES_PER_BUFFER);
			SpriteDMABuffer[Buffer] = NULL;
		}

		SpriteDataBase[Buffer] = NULL;
	}

	if (TextureChunky)
	{
		FreeMem(TextureChunky, TextureChunkySize);
		TextureChunky = NULL;
		TextureSampleBase = NULL;
		TextureChunkySize = 0;
	}

	if (PairExpand)
	{
		FreeMem(PairExpand, PairExpandSize);
		PairExpand = NULL;
		PairExpandSize = 0;
	}

	if (DeltaTab)
	{
		FreeMem(DeltaTab, DeltaTabSize);
		DeltaTab = NULL;
		DeltaTabSize = 0;
	}
}

BOOL Init_RotoZoomer(void)
{
	struct lwmf_Image *RotoBitmap;

	RotoBitmap = lwmf_LoadImage(TEXTURE_FILENAME);
	if (!RotoBitmap)
	{
		return FALSE;
	}

	if (!BuildChunkyTextureFromBitmap(RotoBitmap))
	{
		lwmf_DeleteImage(RotoBitmap);
		return FALSE;
	}

	lwmf_DeleteImage(RotoBitmap);

	DeltaTabSize = sizeof(RotoDelta) * 256u * ROTO_ZOOM_STEPS;
	DeltaTab = (RotoDelta*)AllocCpuMem(DeltaTabSize, 0u);
	if (!DeltaTab)
	{
		Cleanup_RotoZoomer();
		return FALSE;
	}

	PairExpandSize = (ULONG)sizeof(PairExpandSet);
	PairExpand = (PairExpandSet*)AllocCpuMem(PairExpandSize, 0u);
	if (!PairExpand)
	{
		Cleanup_RotoZoomer();
		return FALSE;
	}

	for (UBYTE Buffer = 0; Buffer < 2u; ++Buffer)
	{

		SpriteDMABuffer[Buffer] = (UWORD*)AllocMem(SPRITE_BYTES_PER_BUFFER, MEMF_CHIP | MEMF_CLEAR);
		if (!SpriteDMABuffer[Buffer])
		{
			Cleanup_RotoZoomer();
			return FALSE;
		}
	}

	BuildPairExpandTable();
	BuildMoveTable();
	BuildDeltaTable();
	BuildSpriteBuffers();

	AnglePhase = 0;
	ZoomPhase  = 0;
	MovePhaseX = 0;
	MovePhaseY = 64;

	return TRUE;
}

static void PrepareDrawParams(RotoAsmParams *Params, const RotoDelta *D, UBYTE Buffer, WORD RowU, WORD RowV)
{
	Params->Texture      = TextureSampleBase;
	Params->PlayfieldBase = (UBYTE*)ScreenBitmap[Buffer]->Planes[0];
	Params->SpriteDataBase = SpriteDataBase[Buffer];
	Params->PairExpand   = (const UBYTE*)PairExpand;
	Params->DuDx         = D->DuDx;
	Params->DvDx         = D->DvDx;
	Params->DuDy         = D->DuDy;
	Params->DvDy         = D->DvDy;
	Params->RowU         = RowU;
	Params->RowV         = RowV;
}

static void BuildSpriteSelfTest(UBYTE Buffer)
{
	static const UBYTE TestColors[SPRITE_PAIR_COUNT] = { 1u, 5u, 10u, 15u };
	ULONG *const Base = SpriteDataBase[Buffer];

	for (UWORD y = 0; y < ROTO_ROWS; ++y)
	{
		ULONG *RowEven = Base + ((ULONG)y * SPRITE_LOGICAL_ROW_STRIDE_LONGS);

		for (UBYTE pair = 0; pair < SPRITE_PAIR_COUNT; ++pair)
		{
			const UBYTE Color = TestColors[pair];
			const UWORD Plane0 = (Color & 0x01u) ? 0xFFFFu : 0x0000u;
			const UWORD Plane1 = (Color & 0x02u) ? 0xFFFFu : 0x0000u;
			const UWORD Plane2 = (Color & 0x04u) ? 0xFFFFu : 0x0000u;
			const UWORD Plane3 = (Color & 0x08u) ? 0xFFFFu : 0x0000u;
			const ULONG EvenWords = ((ULONG)Plane0 << 16) | (ULONG)Plane1;
			const ULONG OddWords  = ((ULONG)Plane2 << 16) | (ULONG)Plane3;
			ULONG *Even = RowEven + ((ULONG)pair * SPRITE_PAIR_STRIDE_LONGS);
			ULONG *Odd  = Even + SPRITE_CHANNEL_STRIDE_LONGS;

			Even[0] = EvenWords;
			Even[1] = EvenWords;
			Even[2] = EvenWords;
			Even[3] = EvenWords;

			Odd[0] = OddWords;
			Odd[1] = OddWords;
			Odd[2] = OddWords;
			Odd[3] = OddWords;
		}
	}
}

void Draw_RotoZoomer(UBYTE Buffer)
{
	RotoAsmParams Params;
	const UBYTE ZoomIndex = (UBYTE)(SinTab256[ZoomPhase] >> 1);
	const RotoDelta *D = &DeltaTab[(AnglePhase * ROTO_ZOOM_STEPS) + ZoomIndex];
	const WORD CenterU = MoveTab[MovePhaseX];
	const WORD CenterV = MoveTab[MovePhaseY];
	const WORD BaseRowU = (WORD)(CenterU - (ROTO_HALF_COLUMNS * D->DuDx) - (ROTO_HALF_ROWS * D->DuDy));
	const WORD BaseRowV = (WORD)(CenterV - (ROTO_HALF_COLUMNS * D->DvDx) - (ROTO_HALF_ROWS * D->DvDy));

	DBG_COLOR(0x222);

#if SPRITE_SELFTEST
	BuildSpriteSelfTest(Buffer);
#else
	PrepareDrawParams(&Params, D, Buffer, BaseRowU, BaseRowV);
	DrawRotoHybridAsm(&Params);
#endif

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

#define COPPER_EXTRA_WAIT_WORDS  (((ROTO_VPOS_START + ROTO_DISPLAY_HEIGHT) > 256u) ? 2u : 0u)
#define COPPER_MOD_EVENTS        ((ROTO_ROWS * 2u) - 1u)
#define COPPERWORDS (18u + (NUMBEROFBITPLANES * 4u) + (SPRITE_CHANNEL_COUNT * 4u) + (SCREEN_COLORS * 2u) + (SPRITE_COLORS * 2u) + (COPPER_MOD_EVENTS * 6u) + COPPER_EXTRA_WAIT_WORDS + 2u)

#define MAYBE_INSERT_256_WAIT(ptr_, flag_, vpos_) 	do 	{ 		if (!(flag_) && ((vpos_) >= 256u)) 		{ 			*(ptr_)++ = 0xFFDFu; 			*(ptr_)++ = 0xFFFEu; 			(flag_) = TRUE; 		} 	} while (0)

BOOL Init_CopperList(void)
{
	CopperListSize = COPPERWORDS * sizeof(UWORD);

	if (!(CopperList = (UWORD*)AllocMem(CopperListSize, MEMF_CHIP | MEMF_CLEAR)))
	{
		return FALSE;
	}

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

	CopperList[Index++] = 0x104;
	CopperList[Index++] = 0x0024;

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

	for (UWORD ch = 0; ch < SPRITE_CHANNEL_COUNT; ++ch)
	{
		CopperList[Index++] = (UWORD)(0x0120u + (ch * 4u));
		SPRPTH_Idx[ch] = Index;
		CopperList[Index++] = 0x0000;

		CopperList[Index++] = (UWORD)(0x0122u + (ch * 4u));
		SPRPTL_Idx[ch] = Index;
		CopperList[Index++] = 0x0000;
	}

	for (UWORD i = 0; i < SCREEN_COLORS; ++i)
	{
		CopperList[Index++] = (UWORD)(0x180u + (i * 2u));
		CopperList[Index++] = TexturePalette[i];
	}

	for (UWORD i = 0; i < SPRITE_COLORS; ++i)
	{
		CopperList[Index++] = (UWORD)(0x1A2u + (i * 2u));
		CopperList[Index++] = TexturePalette[i + 1u];
	}

	UWORD *CopperPtr = &CopperList[Index];
	BOOL InsertedLine256Wait = FALSE;

	for (UWORD row = 0; row < ROTO_ROWS; ++row)
	{
		const UWORD AdvanceLine = (UWORD)(ROTO_VPOS_START + (row * CHUNKY_PIXEL_SIZE) + (CHUNKY_PIXEL_SIZE - 1u));

		MAYBE_INSERT_256_WAIT(CopperPtr, InsertedLine256Wait, AdvanceLine);
		*CopperPtr++ = (UWORD)(((AdvanceLine & 0x00FFu) << 8) | 0x0007u);
		*CopperPtr++ = 0xFFFEu;
		*CopperPtr++ = 0x0108u;
		*CopperPtr++ = ROTO_ADVANCE_MOD;
		*CopperPtr++ = 0x010Au;
		*CopperPtr++ = ROTO_ADVANCE_MOD;

		if (row + 1u < ROTO_ROWS)
		{
			const UWORD RepeatLine = (UWORD)(AdvanceLine + 1u);

			MAYBE_INSERT_256_WAIT(CopperPtr, InsertedLine256Wait, RepeatLine);
			*CopperPtr++ = (UWORD)(((RepeatLine & 0x00FFu) << 8) | 0x0007u);
			*CopperPtr++ = 0xFFFEu;
			*CopperPtr++ = 0x0108u;
			*CopperPtr++ = ROTO_REPEAT_MOD;
			*CopperPtr++ = 0x010Au;
			*CopperPtr++ = ROTO_REPEAT_MOD;
		}
	}

	Index = (UWORD)(CopperPtr - CopperList);

	CopperList[Index++] = 0xFFFF;
	CopperList[Index++] = 0xFFFE;

	return TRUE;
}

static void ActivateCopperList(void)
{
	*COP1LC = (ULONG)CopperList;
	*COPJMP1_REG = 0u;
}

void Update_BitplanePointers(UBYTE Buffer)
{
	ULONG Ptr = (ULONG)ScreenBitmap[Buffer]->Planes[0];

	CopperList[BPLPTH_Idx[0]] = (UWORD)(Ptr >> 16);
	CopperList[BPLPTL_Idx[0]] = (UWORD)(Ptr & 0xFFFFu);

	Ptr += ROTO_BUFFER_PLANEBYTES;
	CopperList[BPLPTH_Idx[1]] = (UWORD)(Ptr >> 16);
	CopperList[BPLPTL_Idx[1]] = (UWORD)(Ptr & 0xFFFFu);

	Ptr += ROTO_BUFFER_PLANEBYTES;
	CopperList[BPLPTH_Idx[2]] = (UWORD)(Ptr >> 16);
	CopperList[BPLPTL_Idx[2]] = (UWORD)(Ptr & 0xFFFFu);

	Ptr += ROTO_BUFFER_PLANEBYTES;
	CopperList[BPLPTH_Idx[3]] = (UWORD)(Ptr >> 16);
	CopperList[BPLPTL_Idx[3]] = (UWORD)(Ptr & 0xFFFFu);
}

// =====================================================================
// Cleanup & Main
// =====================================================================

void Cleanup_All(void)
{
	if (OsTakenOver)
	{
		DisableSpriteDMA();
		lwmf_ReleaseOS();
		OsTakenOver = FALSE;
	}

	Cleanup_RotoZoomer();

	if (CopperList)
	{
		FreeMem(CopperList, CopperListSize);
		CopperList = NULL;
	}

	Cleanup_RotoScreenBitmaps();
	lwmf_CloseLibraries();
}

int main(void)
{
	if (lwmf_LoadGraphicsLib() != 0)
	{
		return 20;
	}

	if (!Init_RotoScreenBitmaps())
	{
		Cleanup_All();
		return 20;
	}

	if (!Init_RotoZoomer())
	{
		Cleanup_All();
		return 20;
	}

	if (!Init_CopperList())
	{
		Cleanup_All();
		return 20;
	}

	lwmf_TakeOverOS();
	OsTakenOver = TRUE;

	/* Build a valid first frame before enabling sprite DMA. */
	Draw_RotoZoomer(0);
	Update_BitplanePointers(0);
	CommitSpritePointers(0);
	ActivateCopperList();
	EnableSpriteDMA();

	{
		UBYTE CurrentBuffer = 1;

		while (*CIAA_PRA & 0x40)
		{
			Draw_RotoZoomer(CurrentBuffer);

			DBG_COLOR(0x0F0);
			lwmf_WaitVertBlank();
			DBG_COLOR(0x000);

			Update_BitplanePointers(CurrentBuffer);
			CommitSpritePointers(CurrentBuffer);
			CurrentBuffer ^= 1u;
		}
	}

	Cleanup_All();
	return 0;
}
