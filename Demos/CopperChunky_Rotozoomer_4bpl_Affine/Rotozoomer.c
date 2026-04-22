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
#define DEBUG                   0

#if DEBUG
	#define DBG_COLOR(c) (*COLOR00 = (c))
#else
	#define DBG_COLOR(c) ((void)0)
#endif

extern void Draw_RotoZoomerAsm(__reg("d0") UBYTE Buffer);

#if DEBUG
static void Draw_RotoZoomer(UBYTE Buffer)
{
	DBG_COLOR(0xF00);
	Draw_RotoZoomerAsm(Buffer);
	DBG_COLOR(0x000);
}
#else
	#define Draw_RotoZoomer(Buffer) Draw_RotoZoomerAsm((Buffer))
#endif

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

#define ROTO_HALF_COLUMNS        (ROTO_COLUMNS / 2)
#define ROTO_HALF_ROWS           (ROTO_ROWS / 2)
#define ROTO_FRAME_COUNT         256u
#define ROTO_ANGLE_PHASE_STEP    2u
#define ROTO_MOVE_Y_PHASE_START  64u
#define ROTO_MOVE_Y_PHASE_STEP   2u

// Precalculated frame table. The whole animation repeats after 256 frames,
// so every frame can be represented by a single prebuilt record.
//
// The 16-byte layout is intentional so the ASM renderer can address an entry
// with "frame << 4".
typedef struct RotoFrame
{
	WORD RowU;
	WORD RowV;
	WORD DuDx;
	WORD DvDx;
	WORD RowStepU;
	WORD RowStepV;
	WORD Pad0;
	WORD Pad1;
} RotoFrame;

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

UBYTE *TextureChunky = NULL;
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

PairExpandSet PairExpand;
RotoFrame *FrameTab = NULL;
UBYTE *DestBase[2] = { NULL, NULL };
UBYTE FramePhase = 0;

static ULONG FrameTabSize = 0;

// =====================================================================
// Texture loading and precomputation
// =====================================================================

static void BuildPairExpandTable(void)
{
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

static void BuildFrameTable(void)
{
	for (UWORD Frame = 0; Frame < ROTO_FRAME_COUNT; ++Frame)
	{
		const UBYTE AnglePhase = (UBYTE)(Frame * ROTO_ANGLE_PHASE_STEP);
		const UBYTE ZoomPhase = (UBYTE)(Frame * ROTO_ZOOM_SPEED);
		const UBYTE MovePhaseX = (UBYTE)Frame;
		const UBYTE MovePhaseY = (UBYTE)(ROTO_MOVE_Y_PHASE_START + (Frame * ROTO_MOVE_Y_PHASE_STEP));

		const UBYTE ZoomIndex = (UBYTE)(SinTab256[ZoomPhase] >> 1);
		const WORD ZoomMod = (WORD)(((WORD)ZoomIndex << 1) - 32);
		const WORD Zoom = (WORD)(ROTO_ZOOM_BASE + ((ZoomMod * ROTO_ZOOM_AMPLITUDE) >> 5));

		const WORD SinV = (WORD)SinTab256[AnglePhase] - 32;
		const WORD CosV = (WORD)SinTab256[(UBYTE)(AnglePhase + 64u)] - 32;

		const WORD DuDx = (WORD)(((LONG)CosV * (LONG)Zoom) >> 5);
		const WORD DvDx = (WORD)(((LONG)SinV * (LONG)Zoom) >> 5);

		const WORD CenterU = (WORD)((64 << 8) + (((WORD)SinTab256[MovePhaseX] - 32) << 7));
		const WORD CenterV = (WORD)((64 << 8) + (((WORD)SinTab256[MovePhaseY] - 32) << 7));

		RotoFrame *F = &FrameTab[Frame];

		F->RowU = (WORD)(CenterU - (ROTO_HALF_COLUMNS * DuDx) + (ROTO_HALF_ROWS * DvDx));
		F->RowV = (WORD)(CenterV - (ROTO_HALF_COLUMNS * DvDx) - (ROTO_HALF_ROWS * DuDx));
		F->DuDx = DuDx;
		F->DvDx = DvDx;
		F->RowStepU = (WORD)(-DvDx - (ROTO_COLUMNS * DuDx));
		F->RowStepV = (WORD)( DuDx - (ROTO_COLUMNS * DvDx));
	}
}

static void Init_RotoZoomer(void)
{
	struct lwmf_Image *RotoBitmap;

	RotoBitmap = lwmf_LoadImage(TEXTURE_FILENAME);

	FrameTabSize = sizeof(RotoFrame) * ROTO_FRAME_COUNT;
	FrameTab = (RotoFrame*)lwmf_AllocCpuMem(FrameTabSize, MEMF_CLEAR);

	BuildChunkyTextureFromBitmap(RotoBitmap);

	lwmf_DeleteImage(RotoBitmap);

	BuildPairExpandTable();
	BuildFrameTable();

	DestBase[0] = (UBYTE*)ScreenBitmap[0]->Planes[0] + (ULONG)ROTO_START_BYTE;
	DestBase[1] = (UBYTE*)ScreenBitmap[1]->Planes[0] + (ULONG)ROTO_START_BYTE;
	FramePhase = 0;
}

static void Cleanup_RotoZoomer(void)
{
	FreeMem(TextureChunky, TextureChunkySize);
	TextureChunky = NULL;
	TextureChunkySize = 0;

	FreeMem(FrameTab, FrameTabSize);
	FrameTab = NULL;
	FrameTabSize = 0;
}

// =====================================================================
// Copper list
// =====================================================================

static UWORD *CopperList     = NULL;
static ULONG  CopperListSize = 0;

static UWORD BPLPTH_Idx[ROTO_BITPLANES];
static UWORD BPLPTL_Idx[ROTO_BITPLANES];

#define COPPER_EXTRA_WAIT_WORDS  (((ROTO_VPOS_START + ROTO_DISPLAY_HEIGHT) > 256) ? 2 : 0)
#define COPPERWORDS (16 + (ROTO_BITPLANES * 4) + (SCREEN_COLORS * 2) + (ROTO_DISPLAY_HEIGHT * 6) + COPPER_EXTRA_WAIT_WORDS + 2)

static void Init_CopperList(void)
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

	for (UWORD p = 0; p < ROTO_BITPLANES; ++p)
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

static void Update_BitplanePointers(UBYTE Buffer)
{
	ULONG Ptr = (ULONG)DestBase[Buffer];

	for (UWORD p = 0; p < ROTO_BITPLANES; ++p)
	{
		CopperList[BPLPTH_Idx[p]] = (UWORD)(Ptr >> 16);
		CopperList[BPLPTL_Idx[p]] = (UWORD)(Ptr & 0xFFFFu);
		Ptr += BYTESPERROW;
	}
}

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
