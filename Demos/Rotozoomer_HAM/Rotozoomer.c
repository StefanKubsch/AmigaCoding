//**********************************************************************
//* 4x4 HAM / 7-bitplane Copper Rotozoomer                             *
//* 4 DMA bitplanes + BPL5DAT/BPL6DAT via Copper                       *
//* Amiga 500 OCS                                                      *
//*                                                                    *
//* Source image: 128x128_4pl_2.iff                                    *
//* Runtime texture: RGB444 words, duplicated to 256x128 internally    *
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
#define DEBUG 0

#if DEBUG
	#define DBG_COLOR(c) (*COLOR00 = (c))
#else
	#define DBG_COLOR(c) ((void)0)
#endif

extern void Draw_RotoZoomerAsm(__reg("d0") UBYTE Buffer);

// =====================================================================
// Effect constants
// =====================================================================

#define TEXTURE_FILENAME         "128x128_4pl_2.iff"
#define TEXTURE_SOURCE_WIDTH     128
#define TEXTURE_SOURCE_HEIGHT    128
#define TEXTURE_WIDTH            256
#define TEXTURE_HEIGHT           TEXTURE_SOURCE_HEIGHT

#define SCREEN_COLORS            16

// Base zoom
// Larger value  = further out  (more of the texture visible)
// Smaller value = further in   (less of the texture visible)
#define ROTO_ZOOM_BASE           384
// Zoom animation amplitude
#define ROTO_ZOOM_AMPLITUDE      128

#define CHUNKY_PIXEL_SIZE        4
#define ROTO_VISIBLE_COLUMNS     50
#define ROTO_GUARD_COLUMNS       2
#define ROTO_COLUMNS             (ROTO_VISIBLE_COLUMNS + ROTO_GUARD_COLUMNS)
#define ROTO_ROWS                50
#define ROTO_DISPLAY_WIDTH       (ROTO_COLUMNS * CHUNKY_PIXEL_SIZE)
#define ROTO_DISPLAY_HEIGHT      (ROTO_ROWS * CHUNKY_PIXEL_SIZE)

// Byte aligned on purpose so the 208 fetched pixels are centered in the
// normal 320 pixel wide screen bitmap.
#define ROTO_START_X             ((((SCREENWIDTH - ROTO_DISPLAY_WIDTH) >> 1)) & ~7)
#define ROTO_START_BYTE          (ROTO_START_X >> 3)

#define INTERLEAVED_STRIDE       (BYTESPERROW * NUMBEROFBITPLANES)

#define ROTO_FETCH_WORDS         (ROTO_DISPLAY_WIDTH / 16)
#define ROTO_FETCH_BYTES         (ROTO_DISPLAY_WIDTH / 8)
#define ROTO_REPEAT_MOD          ((UWORD)(-(WORD)ROTO_FETCH_BYTES))
#define ROTO_ADVANCE_MOD         ((UWORD)(INTERLEAVED_STRIDE - ROTO_FETCH_BYTES))

#define VPOS_OFFSET              0x2C

/*
 * Keep the 208-pixel lowres fetch window vertically centered inside the
 * normal PAL 256 line playfield area.
 *
 * The HSTART/HSTOP values below are PAL/OCS-friendly defaults for a 208 pixel
 * wide centered window. If your monitor setup differs, tune only these two
 * horizontal bytes.
 */
#define ROTO_VPOS_START          (VPOS_OFFSET + ((SCREENHEIGHT - ROTO_DISPLAY_HEIGHT) / 2))
#define ROTO_VPOS_STOP           (ROTO_VPOS_START + ROTO_DISPLAY_HEIGHT)
#define ROTO_DIW_HSTART          0x00B9
#define ROTO_DIW_HSTOP           0x0089
#define ROTO_DIWSTRT             (UWORD)(((ROTO_VPOS_START & 0xFFu) << 8) | ROTO_DIW_HSTART)
#define ROTO_DIWSTOP             (UWORD)(((ROTO_VPOS_STOP  & 0xFFu) << 8) | ROTO_DIW_HSTOP)
#define ROTO_DDFSTRT             0x0058
#define ROTO_DDFSTOP             (UWORD)(ROTO_DDFSTRT + ((ROTO_FETCH_WORDS - 1u) * 8u))

// Copper writes the BPL5DAT/BPL6DAT control words slightly before the
// matching DMA word is fetched. +/-2 on the base value is the only tuning
// point if a particular machine/monitor needs it.
#define ROTO_BPLDAT_HPOS_BASE    (UWORD)(ROTO_DDFSTRT - 4u)
#define ROTO_BPLDAT_HPOS_STEP    8u

// Use the OCS 7-bitplane quirk: ask for 7 planes in HAM mode.
// Agnus only fetches 4 DMA planes, while Denise still combines 6 visible bits.
#define ROTO_BPLCON0             0x7800

#define ROTO_HALF_COLUMNS        (ROTO_VISIBLE_COLUMNS / 2)
#define ROTO_HALF_ROWS           (ROTO_ROWS / 2)
#define ROTO_ANGLE_PHASE_STEP    2

// =====================================================================
// Fixed HAM control words for one 16-pixel fetch word (= four 4x1 texels)
// =====================================================================
//
// Visible texels use RGBB control sequence per 4-pixel texel:
//   R = 10, G = 11, B = 01, B = 01
//
// The left guard texel is encoded as 00,R,G,B with zero data, so the row starts
// from deterministic black before the first visible texel is built.
//
// The right guard texel uses the same black sequence at the end of the row.
//
// Plane 5 is the low control bit, plane 6 the high control bit.
// =====================================================================

static const UWORD HamCtrlPlane5[ROTO_FETCH_WORDS] =
{
	0x3777,
	0x7777, 0x7777, 0x7777, 0x7777, 0x7777, 0x7777,
	0x7777, 0x7777, 0x7777, 0x7777, 0x7777,
	0x7773
};

static const UWORD HamCtrlPlane6[ROTO_FETCH_WORDS] =
{
	0x6CCC,
	0xCCCC, 0xCCCC, 0xCCCC, 0xCCCC, 0xCCCC, 0xCCCC,
	0xCCCC, 0xCCCC, 0xCCCC, 0xCCCC, 0xCCCC,
	0xCCC6
};

// =====================================================================
// Sine table, motion table and frame table
// =====================================================================

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

static WORD MoveTab[256];
RotoFrame FrameTab[256];
UBYTE FramePhase = 0;

// Values span 0..63, so signed values are obtained via (value - 32).
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
// Texture, palette, destination bases and pack LUT for the ASM hotloop
// =====================================================================

UWORD *TextureRGB444 = NULL;
ULONG TextureRGB444Size = 0;
UWORD TextureBasePalette[SCREEN_COLORS];
ULONG HamPackLUT[4096u];
UBYTE *DestBase[2] = { NULL, NULL };

// =====================================================================
// Texture loading and precomputation
// =====================================================================

static void BuildHamPackLUT(void)
{
	for (UWORD rgb = 0; rgb < 4096u; ++rgb)
	{
		const UBYTE r = (UBYTE)((rgb >> 8) & 0x0Fu);
		const UBYTE g = (UBYTE)((rgb >> 4) & 0x0Fu);
		const UBYTE b = (UBYTE)(rgb & 0x0Fu);

		const UBYTE p0 = (UBYTE)((((r >> 0) & 1u) << 3) | (((g >> 0) & 1u) << 2) | (((b >> 0) & 1u) << 1) | ((b >> 0) & 1u));
		const UBYTE p1 = (UBYTE)((((r >> 1) & 1u) << 3) | (((g >> 1) & 1u) << 2) | (((b >> 1) & 1u) << 1) | ((b >> 1) & 1u));
		const UBYTE p2 = (UBYTE)((((r >> 2) & 1u) << 3) | (((g >> 2) & 1u) << 2) | (((b >> 2) & 1u) << 1) | ((b >> 2) & 1u));
		const UBYTE p3 = (UBYTE)((((r >> 3) & 1u) << 3) | (((g >> 3) & 1u) << 2) | (((b >> 3) & 1u) << 1) | ((b >> 3) & 1u));

		HamPackLUT[rgb] = ((ULONG)p0 << 24) | ((ULONG)p1 << 16) | ((ULONG)p2 << 8) | (ULONG)p3;
	}
}

static BOOL BuildTextureRGB444FromBitmap(struct lwmf_Image *RotoBitmap)
{
	const UBYTE PlaneCount = RotoBitmap->Image.Depth;
	const UWORD BytesPerRow = RotoBitmap->Image.BytesPerRow;
	const UWORD ColorCount = (UWORD)RotoBitmap->NumberOfColors;

	TextureRGB444Size = (ULONG)TEXTURE_WIDTH * (ULONG)TEXTURE_HEIGHT * sizeof(UWORD);
	TextureRGB444 = (UWORD*)lwmf_AllocCpuMem(TextureRGB444Size, MEMF_CLEAR);
	if (!TextureRGB444)
	{
		return FALSE;
	}

	for (UWORD i = 0; i < SCREEN_COLORS; ++i)
	{
		TextureBasePalette[i] = 0x000u;
	}

	if (RotoBitmap->CRegs)
	{
		for (UWORD i = 0; (i < SCREEN_COLORS) && (i < ColorCount); ++i)
		{
			TextureBasePalette[i] = (UWORD)(RotoBitmap->CRegs[i] & 0x0FFFu);
		}
	}
	else
	{
		for (UWORD i = 0; i < SCREEN_COLORS; ++i)
		{
			const UWORD v = (UWORD)((i * 15u) / 15u);
			TextureBasePalette[i] = (UWORD)((v << 8) | (v << 4) | v);
		}
	}

	// Guard texels use palette index 0 in their direct HAM pixel, so make it black.
	TextureBasePalette[0] = 0x000u;

	/*
	 * Internal texture layout is 256x128 although the source image is 128x128.
	 * Each source row is duplicated horizontally into the second 128-word half.
	 * This lets the ASM hotloop use (U >> 8) directly as a 0..255 texel X value.
	 */
	for (UWORD y = 0; y < TEXTURE_SOURCE_HEIGHT; ++y)
	{
		UWORD *Dst = TextureRGB444 + ((ULONG)y * (ULONG)TEXTURE_WIDTH);

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

			Index &= (SCREEN_COLORS - 1u);
			Dst[x] = TextureBasePalette[Index];
			Dst[x + TEXTURE_SOURCE_WIDTH] = TextureBasePalette[Index];
		}
	}

	return TRUE;
}

static void BuildMoveTable(void)
{
	for (UWORD i = 0; i < 256; ++i)
	{
		MoveTab[i] = (WORD)((64 << 8) + (((WORD)SinTab256[i] - 32) << 7));
	}
}

static void BuildFrameTable(void)
{
	for (UWORD phase = 0; phase < 256u; ++phase)
	{
		const UBYTE Angle = (UBYTE)(phase * ROTO_ANGLE_PHASE_STEP);
		const UBYTE ZoomIndex = (UBYTE)(SinTab256[phase] >> 1);
		const WORD SinV = (WORD)SinTab256[Angle] - 32;
		const WORD CosV = (WORD)SinTab256[(UBYTE)(Angle + 64u)] - 32;
		const WORD ZoomMod = (WORD)(((WORD)ZoomIndex << 1) - 32);
		const WORD Zoom = (WORD)(ROTO_ZOOM_BASE + ((ZoomMod * ROTO_ZOOM_AMPLITUDE) >> 5));
		const WORD DuDx = (WORD)(((LONG)CosV * (LONG)Zoom) >> 5);
		const WORD DvDx = (WORD)(((LONG)SinV * (LONG)Zoom) >> 5);
		const WORD RowStepU = (WORD)(-DvDx);
		const WORD RowStepV = DuDx;
		const WORD CenterU = MoveTab[phase];
		const WORD CenterV = MoveTab[(UBYTE)(phase + 64u)];
		RotoFrame *Frame = &FrameTab[phase];

		Frame->DuDx = DuDx;
		Frame->DvDx = DvDx;
		Frame->RowStepU = RowStepU;
		Frame->RowStepV = RowStepV;
		Frame->RowU = (WORD)(CenterU - (ROTO_HALF_COLUMNS * DuDx) - (ROTO_HALF_ROWS * RowStepU));
		Frame->RowV = (WORD)(CenterV - (ROTO_HALF_COLUMNS * DvDx) - (ROTO_HALF_ROWS * RowStepV));
		Frame->Pad0 = 0;
		Frame->Pad1 = 0;
	}
}

static BOOL Init_RotoZoomer(void)
{
	struct lwmf_Image *RotoBitmap;

	RotoBitmap = lwmf_LoadImage(TEXTURE_FILENAME);

	if (!RotoBitmap)
	{
		return FALSE;
	}

	if ((RotoBitmap->Width != TEXTURE_SOURCE_WIDTH) ||
		(RotoBitmap->Height != TEXTURE_SOURCE_HEIGHT) ||
		(RotoBitmap->Image.Depth != 4))
	{
		PutStr("Expected 128x128 4-plane ILBM image.\n");
		lwmf_DeleteImage(RotoBitmap);
		return FALSE;
	}

	if (!BuildTextureRGB444FromBitmap(RotoBitmap))
	{
		lwmf_DeleteImage(RotoBitmap);
		PutStr("Out of memory for RGB444 texture.\n");
		return FALSE;
	}
	lwmf_DeleteImage(RotoBitmap);

	BuildHamPackLUT();
	BuildMoveTable();
	BuildFrameTable();

	DestBase[0] = (UBYTE*)ScreenBitmap[0]->Planes[0] + (ULONG)ROTO_START_BYTE;
	DestBase[1] = (UBYTE*)ScreenBitmap[1]->Planes[0] + (ULONG)ROTO_START_BYTE;
	FramePhase = 0;

	return TRUE;
}

static void Draw_RotoZoomer(UBYTE Buffer)
{
	DBG_COLOR(0xF00);
	Draw_RotoZoomerAsm(Buffer);
	DBG_COLOR(0x000);
}

static void Cleanup_RotoZoomer(void)
{
	if (TextureRGB444)
	{
		FreeMem(TextureRGB444, TextureRGB444Size);
		TextureRGB444 = NULL;
		TextureRGB444Size = 0;
	}
}

// =====================================================================
// Copper list
// =====================================================================

static UWORD *CopperList = NULL;
static ULONG CopperListSize = 0;

static UWORD BPLPTH_Idx[NUMBEROFBITPLANES];
static UWORD BPLPTL_Idx[NUMBEROFBITPLANES];

// Fixed header:
// DIWSTRT+DIWSTOP+DDFSTRT+DDFSTOP+BPLCON0+BPLCON1+BPL1MOD+BPL2MOD = 16 words
// 4 bitplane pointers = 16 words
// 16 colors = 32 words
// Per displayed line:
//   13 * (WAIT + BPL5DAT + BPL6DAT) = 78 words
//   plus on the first fetch word: BPL1MOD + BPL2MOD = 4 more words
// => 82 words per displayed line
// Moving the window lower crosses beam line 255 once, so one wrap WAIT pair is needed.
// END = 2 words
#define COPPER_EXTRA_WAIT_WORDS  (((ROTO_VPOS_START + ROTO_DISPLAY_HEIGHT) > 256) ? 2 : 0)
#define COPPER_LINE_WORDS        ((ROTO_FETCH_WORDS * 6) + 4)
#define COPPERWORDS              (16 + (NUMBEROFBITPLANES * 4) + (SCREEN_COLORS * 2) + (ROTO_DISPLAY_HEIGHT * COPPER_LINE_WORDS) + COPPER_EXTRA_WAIT_WORDS + 2)

static BOOL Init_CopperList(void)
{
	CopperListSize = (ULONG)COPPERWORDS * sizeof(UWORD);
	CopperList = (UWORD*)AllocMem(CopperListSize, MEMF_CHIP | MEMF_CLEAR);

	if (!CopperList)
	{
		PutStr("Out of Chip RAM for Copper list.\n");
		return FALSE;
	}

	UWORD Index = 0;

	// 208 pixel wide lowres window, vertically centered.
	CopperList[Index++] = 0x8E;
	CopperList[Index++] = ROTO_DIWSTRT;

	CopperList[Index++] = 0x90;
	CopperList[Index++] = ROTO_DIWSTOP;

	CopperList[Index++] = 0x92;
	CopperList[Index++] = ROTO_DDFSTRT;

	CopperList[Index++] = 0x94;
	CopperList[Index++] = ROTO_DDFSTOP;

	// 7 bitplanes requested in HAM mode -> OCS quirk gives 4 DMA planes plus
	// manually writable BPL5DAT/BPL6DAT.
	CopperList[Index++] = 0x100;
	CopperList[Index++] = ROTO_BPLCON0;

	CopperList[Index++] = 0x102;
	CopperList[Index++] = 0x0000;

	CopperList[Index++] = 0x108;
	CopperList[Index++] = ROTO_REPEAT_MOD;
	CopperList[Index++] = 0x10A;
	CopperList[Index++] = ROTO_REPEAT_MOD;

	// Bitplane pointers
	for (UWORD p = 0; p < NUMBEROFBITPLANES; ++p)
	{
		CopperList[Index++] = (UWORD)(0x0E0u + (p * 4u));
		BPLPTH_Idx[p] = Index;
		CopperList[Index++] = 0x0000;

		CopperList[Index++] = (UWORD)(0x0E2u + (p * 4u));
		BPLPTL_Idx[p] = Index;
		CopperList[Index++] = 0x0000;
	}

	// Base palette copied from the ILBM file. HAM visible pixels are generated
	// through BPL5DAT/BPL6DAT, but keeping the 16 base colors useful makes the
	// row primer deterministic and keeps the setup debuggable.
	for (UWORD i = 0; i < SCREEN_COLORS; ++i)
	{
		CopperList[Index++] = (UWORD)(0x180u + (i * 2u));
		CopperList[Index++] = TextureBasePalette[i];
	}

	UWORD *CopperPtr = &CopperList[Index];

	for (UWORD y = 0; y < ROTO_DISPLAY_HEIGHT; ++y)
	{
		const UWORD Mod = ((y & 3u) == 3u) ? ROTO_ADVANCE_MOD : ROTO_REPEAT_MOD;
		const UWORD VPos = (UWORD)(ROTO_VPOS_START + y);

		for (UWORD w = 0; w < ROTO_FETCH_WORDS; ++w)
		{
			const UWORD HPos = (UWORD)(ROTO_BPLDAT_HPOS_BASE + (w * ROTO_BPLDAT_HPOS_STEP));
			const UWORD WaitWord = (UWORD)((((VPos & 0x00FFu) << 8) | (HPos & 0x00FEu) | 0x0001u) |
			                               ((VPos & 0x0100u) ? 0x8000u : 0x0000u));

			*CopperPtr++ = WaitWord;
			*CopperPtr++ = 0xFFFE;

			if (w == 0)
			{
				*CopperPtr++ = 0x108;
				*CopperPtr++ = Mod;
				*CopperPtr++ = 0x10A;
				*CopperPtr++ = Mod;
			}

			*CopperPtr++ = 0x118;
			*CopperPtr++ = HamCtrlPlane5[w];
			*CopperPtr++ = 0x11A;
			*CopperPtr++ = HamCtrlPlane6[w];
		}
	}

	Index = (UWORD)(CopperPtr - CopperList);

	CopperList[Index++] = 0xFFFF;
	CopperList[Index++] = 0xFFFE;

	*COP1LC = (ULONG)CopperList;
	*(volatile UWORD*)0xDFF088 = 0;
	return TRUE;
}

static void Update_BitplanePointers(UBYTE Buffer)
{
	ULONG Ptr = (ULONG)DestBase[Buffer];

	for (UWORD p = 0; p < NUMBEROFBITPLANES; ++p)
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

	if (CopperList)
	{
		FreeMem(CopperList, CopperListSize);
		CopperList = NULL;
		CopperListSize = 0;
	}

	lwmf_CleanupScreenBitmaps();
	lwmf_CleanupAll();
}

int main(void)
{
	if (lwmf_LoadGraphicsLib())
	{
		return 20;
	}

	if (!lwmf_InitScreenBitmaps())
	{
		lwmf_CleanupAll();
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
