//**********************************************************************
//* Amiga 1200 Intro                                                   *
//* Will run on Amiga 500, but very slow                               *
//*                                                                    *
//* (C) 2026 by Stefan Kubsch                                          *
//* Project for vbcc                                                   *
//*                                                                    *
//* Compile & link with:                                               *
//* make_Build.cmd / make_ADF.cmd                                      *
//*                                                                    *
//* Quit with mouse click                                              *
//**********************************************************************

#include "lwmf/lwmf.h"

#define HWREG_W(a) (*(volatile UWORD *)(a))
#define HWREG_L(a) (*(volatile ULONG *)(a))

// =====================================================================
// MODPlayer (ptplayer)
// =====================================================================

static struct MODFile MOD_Demosong;

// =====================================================================
// Sine table, used by both the sine scroller effects  and the plasma
// =====================================================================

// Shared sine table (256 entries, values 0..63, one full period)
static const UBYTE SinTab256[256] =
	{
		32, 32, 33, 34, 35, 35, 36, 37, 38, 38, 39, 40, 41, 41, 42, 43, 44, 44, 45, 46, 46, 47, 48, 48, 49, 50, 50, 51, 51, 52, 53, 53,
		54, 54, 55, 55, 56, 56, 57, 57, 58, 58, 59, 59, 59, 60, 60, 60, 61, 61, 61, 61, 62, 62, 62, 62, 62, 63, 63, 63, 63, 63, 63, 63,
		63, 63, 63, 63, 63, 63, 63, 63, 62, 62, 62, 62, 62, 61, 61, 61, 61, 60, 60, 60, 59, 59, 59, 58, 58, 57, 57, 56, 56, 55, 55, 54,
		54, 53, 53, 52, 51, 51, 50, 50, 49, 48, 48, 47, 46, 46, 45, 44, 44, 43, 42, 41, 41, 40, 39, 38, 38, 37, 36, 35, 35, 34, 33, 32,
		32, 31, 30, 29, 28, 28, 27, 26, 25, 25, 24, 23, 22, 22, 21, 20, 19, 19, 18, 17, 17, 16, 15, 15, 14, 13, 13, 12, 12, 11, 10, 10,
		9, 9, 8, 8, 7, 7, 6, 6, 5, 5, 4, 4, 4, 3, 3, 3, 2, 2, 2, 2, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9,
		9, 10, 10, 11, 12, 12, 13, 13, 14, 15, 15, 16, 17, 17, 18, 19, 19, 20, 21, 22, 22, 23, 24, 25, 25, 26, 27, 28, 28, 29, 30, 31};

// =====================================================================
// Bouncing Text Logo
// =====================================================================

static UBYTE *LogoBlitData = NULL;
static ULONG LogoBlitDataSize = 0;
static UBYTE LogoOldX[2] = {64, 64};
static UBYTE LogoOldY[2] = {19, 19};

static const UWORD LogoPalette[8] = {0x003, 0x368, 0x134, 0x012, 0x246, 0x146, 0x123, 0x001};

#define LOGO_WIDTH 192
#define LOGO_HEIGHT 46
#define LOGO_PLANES 3
#define LOGO_WORDS (LOGO_WIDTH >> 4)
#define LOGO_PADDED_WORDS (LOGO_WORDS + 1)
#define LOGO_PADDED_ROW_BYTES (LOGO_PADDED_WORDS << 1)
#define LOGO_BLIT_LINES (LOGO_HEIGHT * LOGO_PLANES)
#define LOGO_STEPS 256
#define LOGO_INDEX_STEP 3

static const UBYTE LogoSinTabX[LOGO_STEPS] =
	{
		64, 65, 66, 66, 68, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78,
		79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 92, 92, 94, 94,
		96, 97, 98, 100, 101, 102, 103, 105, 106, 108, 109, 111, 112, 113, 113, 115,
		116, 117, 118, 119, 119, 120, 120, 121, 122, 122, 123, 123, 123, 124, 124, 124,
		124, 124, 124, 124, 123, 123, 122, 122, 122, 121, 121, 121, 119, 119, 118, 117,
		116, 115, 113, 113, 111, 111, 109, 108, 105, 105, 103, 103, 100, 100, 98, 98,
		95, 94, 94, 92, 92, 90, 90, 88, 88, 86, 86, 84, 84, 82, 82, 80,
		80, 78, 78, 76, 76, 74, 74, 72, 72, 71, 70, 69, 68, 66, 66, 65,
		64, 63, 62, 60, 60, 59, 58, 58, 56, 55, 55, 54, 53, 52, 51, 49,
		49, 48, 47, 46, 45, 43, 42, 42, 40, 39, 37, 37, 36, 35, 34, 32,
		31, 30, 29, 27, 26, 25, 23, 22, 21, 19, 18, 17, 15, 15, 14, 12,
		12, 11, 10, 9, 9, 7, 7, 7, 7, 5, 5, 5, 4, 4, 4, 4,
		4, 4, 5, 5, 5, 6, 6, 6, 7, 8, 9, 9, 10, 11, 12, 13,
		14, 15, 16, 17, 19, 20, 22, 23, 25, 26, 28, 29, 30, 31, 32, 33,
		35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50,
		51, 52, 52, 54, 54, 56, 56, 58, 58, 60, 60, 61, 62, 63, 64, 65};

static const UBYTE LogoSinTabY[LOGO_STEPS] =
	{
		19, 19, 20, 21, 21, 22, 23, 23, 24, 24, 25, 25, 26, 26, 27, 27,
		28, 28, 29, 29, 30, 30, 31, 31, 32, 32, 33, 33, 34, 34, 34, 35,
		35, 36, 36, 36, 37, 37, 37, 37, 37, 37, 37, 37, 37, 37, 36, 35,
		35, 34, 34, 33, 33, 31, 31, 30, 29, 28, 27, 25, 25, 24, 22, 21,
		18, 18, 16, 16, 14, 13, 11, 11, 10, 8, 8, 7, 5, 5, 5, 4,
		3, 3, 2, 2, 2, 2, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3,
		3, 4, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10,
		11, 11, 12, 12, 13, 13, 14, 14, 15, 16, 16, 17, 17, 18, 18, 19,
		20, 20, 21, 21, 22, 22, 23, 24, 25, 25, 26, 26, 27, 27, 28, 28,
		29, 29, 30, 30, 31, 31, 32, 32, 32, 33, 33, 33, 34, 34, 35, 35,
		35, 36, 36, 36, 36, 37, 37, 37, 37, 37, 37, 37, 36, 36, 36, 34,
		34, 34, 33, 32, 32, 30, 30, 29, 28, 26, 26, 25, 23, 22, 21, 19,
		16, 16, 14, 14, 12, 11, 9, 9, 8, 7, 6, 6, 5, 4, 4, 4,
		2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 3, 3,
		3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11,
		11, 12, 13, 13, 14, 14, 15, 15, 16, 16, 17, 18, 18, 19, 19, 20};

static BOOL Init_TextLogo(void)
{
	extern UBYTE TextLogo[];
	extern UBYTE TextLogo_end[];
	struct lwmf_Image *LogoBitmap;

	if (!(LogoBitmap = lwmf_LoadImageMem(TextLogo, (ULONG)(TextLogo_end - TextLogo))))
	{
		return FALSE;
	}

	LogoBlitDataSize = (ULONG)LOGO_PADDED_ROW_BYTES * LOGO_BLIT_LINES;

	if (!(LogoBlitData = (UBYTE *)AllocMem(LogoBlitDataSize, MEMF_CHIP | MEMF_CLEAR)))
	{
		lwmf_DeleteImage(LogoBitmap);
		return FALSE;
	}

	const UWORD SrcBPR = LogoBitmap->Image.BytesPerRow;
	UBYTE *dst = LogoBlitData;

	for (UWORD y = 0; y < LOGO_HEIGHT; ++y)
	{
		for (UBYTE p = 0; p < LOGO_PLANES; ++p)
		{
			const UBYTE *src = (const UBYTE *)LogoBitmap->Image.Planes[p] + (ULONG)y * SrcBPR;
			CopyMem((APTR)src, dst, LOGO_WORDS << 1);
			dst += LOGO_PADDED_ROW_BYTES;
		}
	}

	lwmf_DeleteImage(LogoBitmap);
	return TRUE;
}

static void Blit_TextLogo(UBYTE Buffer, UWORD PosX, UWORD PosY)
{
	const UWORD Shift = PosX & 15;
	UBYTE *Dst = (UBYTE *)ScreenBitmap[Buffer]->Planes[0] + (ULONG)PosY * SCREENWIDTHTOTAL + ((PosX & WORD_ALIGN_MASK) >> 3);

	lwmf_WaitBlitter();

	HWREG_W(BLTCON0) = (UWORD)((Shift << 12) | BLTCON0_COPY_A_TO_D);
	HWREG_W(BLTCON1) = 0x0000;
	HWREG_W(BLTAFWM) = 0xFFFF;
	HWREG_W(BLTALWM) = 0xFFFF;
	HWREG_W(BLTAMOD) = 0x0000;
	HWREG_W(BLTDMOD) = (UWORD)(BYTESPERROW - LOGO_PADDED_ROW_BYTES);
	HWREG_L(BLTAPTH) = (ULONG)LogoBlitData;
	HWREG_L(BLTDPTH) = (ULONG)Dst;
	HWREG_W(BLTSIZE) = (UWORD)((LOGO_BLIT_LINES << 6) | LOGO_PADDED_WORDS);
}

static void BlitClearTextLogoOld(UBYTE Buffer)
{
	const UWORD PosX = LogoOldX[Buffer];
	const UWORD PosY = LogoOldY[Buffer];
	UBYTE *Dst = (UBYTE *)ScreenBitmap[Buffer]->Planes[0] + (ULONG)PosY * SCREENWIDTHTOTAL + ((PosX & WORD_ALIGN_MASK) >> 3);

	lwmf_WaitBlitter();

	HWREG_L(BLTCON0) = 0x01000000;
	HWREG_W(BLTDMOD) = (UWORD)(BYTESPERROW - LOGO_PADDED_ROW_BYTES);
	HWREG_L(BLTDPTH) = (ULONG)Dst;
	HWREG_W(BLTSIZE) = (UWORD)((LOGO_BLIT_LINES << 6) | LOGO_PADDED_WORDS);
}

static void Draw_TextLogo(UBYTE Buffer)
{
	static UBYTE LogoIndex = 0;

	const UBYTE PosX = LogoSinTabX[LogoIndex];
	const UBYTE PosY = LogoSinTabY[LogoIndex];

	Blit_TextLogo(Buffer, PosX, PosY);

	LogoOldX[Buffer] = PosX;
	LogoOldY[Buffer] = PosY;

	LogoIndex += LOGO_INDEX_STEP;
}

static void Cleanup_TextLogo(void)
{
	if (LogoBlitData)
	{
		FreeMem(LogoBlitData, LogoBlitDataSize);
		LogoBlitData = NULL;
	}
}

// =====================================================================
// Sine Scroller
// =====================================================================

#define SCROLLER_FEED 2
#define SCROLLER_CHAR_HEIGHT 20
// Stride between rows in an interleaved bitmap: all 3 planes are laid out consecutively per row.
// This is independent of how many planes the Copper displays in a given screen region.
#define INTERLEAVED_STRIDE (BYTESPERROW * NUMBEROFBITPLANES)

#define SCROLLER_CLEAR_START (SCROLLER_START_LINE - SHADOW_DY)
#define SCROLLER_CLEAR_LINES (SCROLLER_MIRROR_LINE - SCROLLER_CLEAR_START)

static void BlitClearPlane0Lines(UWORD StartLine, UWORD Lines, UBYTE *Target)
{
	lwmf_WaitBlitter();

	HWREG_W(BLTCON0) = 0x0100;
	HWREG_W(BLTCON1) = 0x0000;
	HWREG_W(BLTDMOD) = INTERLEAVED_STRIDE - BYTESPERROW;
	HWREG_L(BLTDPTH) = (ULONG)(Target + (ULONG)StartLine * INTERLEAVED_STRIDE);
	HWREG_W(BLTSIZE) = (UWORD)((Lines << 6) | (BYTESPERROW >> 1));
}

static struct Scrollfont
{
	UWORD Length;
	WORD ScrollX;
	UBYTE *ColumnBits;
	WORD *ColumnDst;
	UWORD ColumnCount;
	UWORD FirstVisibleColumn;
} Font;

// Precomputed per screen-X: row offset + byte offset combined.
// = (192 + sineDisp) * INTERLEAVED_STRIDE + (x >> 3)
// Eliminates one shift + add per column in the inner loop.
static UWORD *ScrollRowOffset = NULL;
static ULONG ScrollRowOffsetSize = 0;
static ULONG FontColumnDstSize = 0;
static ULONG FontColumnBitsSize = 0;
static UBYTE ScrollShiftLUT[4][4];

// Precomputed RGB4 rainbow color table, indexed by (line*3 + phase) & 0xFF.
static UWORD *RainbowTab = NULL;
static UWORD *RainbowTabDim = NULL;
static ULONG RainbowTabSize = 0;

static BOOL Init_SineScroller(void)
{
	struct lwmf_Image *FontBitmap;

	ScrollRowOffsetSize = sizeof(UWORD) * SCREENWIDTH;

	if (!(ScrollRowOffset = (UWORD *)lwmf_AllocCpuMem(ScrollRowOffsetSize, MEMF_CLEAR)))
	{
		return FALSE;
	}

	// SinTab256: one full period over 256 entries mapped to 320 pixels
	// centre=192, amplitude=14 (rows 178..206), stride=120
	// Byte offset (x >> 3) is merged in so Draw only needs one table lookup.
	for (UWORD x = 0; x < SCREENWIDTH; ++x)
	{
		const WORD s = (WORD)SinTab256[(UWORD)x * 256 / SCREENWIDTH] - 32;
		ScrollRowOffset[x] = (UWORD)((192 + ((s * 14 + 16) >> 5)) * INTERLEAVED_STRIDE + (x >> 3));
	}

	for (UBYTE s = 0; s < 4; ++s)
	{
		const UBYTE shift = (UBYTE)(6 - (s << 1));

		for (UBYTE v = 0; v < 4; ++v)
		{
			ScrollShiftLUT[s][v] = (UBYTE)(v << shift);
		}
	}

	// Precompute RainbowTab[256]: full RGB4 color for each possible idx value.
	RainbowTabSize = sizeof(UWORD) * 512;

	if (!(RainbowTab = (UWORD *)lwmf_AllocCpuMem(RainbowTabSize, MEMF_CLEAR)))
	{
		FreeMem(ScrollRowOffset, ScrollRowOffsetSize);
		ScrollRowOffset = NULL;
		return FALSE;
	}

	RainbowTabDim = RainbowTab + 256;

	for (UWORD i = 0; i < 256; ++i)
	{
		const UBYTE r = SinTab256[i] >> 2;
		const UBYTE g = SinTab256[(UBYTE)(i + 85)] >> 2;
		const UBYTE b = SinTab256[(UBYTE)(i + 170)] >> 2;
		const UWORD c = (UWORD)((r << 8) | (g << 4) | b);

		RainbowTab[i] = c;
		RainbowTabDim[i] = (c >> 1) & 0x0777;
	}

	extern UBYTE SineScroller[];
	extern UBYTE SineScroller_end[];

	if (!(FontBitmap = lwmf_LoadImageMem(SineScroller, (ULONG)(SineScroller_end - SineScroller))))
	{
		FreeMem(RainbowTab, RainbowTabSize);
		RainbowTab = NULL;
		FreeMem(ScrollRowOffset, ScrollRowOffsetSize);
		ScrollRowOffset = NULL;
		return FALSE;
	}

	const char *Text = "...WELL, WELL...NOT PERFECT, BUT STILL WORKING ON IT !!! HAVE FUN WATCHING THE DEMO AND ENJOY YOUR AMIGA !!! MUSIC - BEAMS OF LIGHT BY WALKMAN 1989...CODE AND GFX - DEEP4 2026...";
	const char *CharMap = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!-,+?*()";
	const WORD Feed = SCROLLER_FEED;
	const WORD CharWidth = 15;
	const UBYTE CharHeight = SCROLLER_CHAR_HEIGHT;
	const WORD CharOverallWidth = CharWidth + 1;

	Font.ScrollX = SCREENWIDTH;
	Font.Length = 0;
	Font.ColumnBits = NULL;
	Font.ColumnDst = NULL;
	Font.ColumnCount = 0;
	Font.FirstVisibleColumn = 0;

	UWORD TextLength = 0;

	while (Text[TextLength] != 0x00)
	{
		++TextLength;
	}

	// Build char lookup: char -> font X offset (-1 = not mapped)
	WORD CharLookup[128];

	for (UWORD k = 0; k < 128; ++k)
	{
		CharLookup[k] = -1;
	}

	UWORD MapPos = 0;

	for (const char *p = CharMap; *p != 0x00; ++p)
	{
		CharLookup[(UBYTE)*p] = MapPos;
		MapPos += CharOverallWidth;
	}

	Font.Length = TextLength * CharOverallWidth;

	const UWORD ColsPerChar = (UWORD)((CharWidth + Feed - 1) / Feed);
	const UWORD MaxColumns = TextLength * ColsPerChar;

	FontColumnDstSize = sizeof(WORD) * MaxColumns;
	if (!(Font.ColumnDst = (WORD *)lwmf_AllocCpuMem(FontColumnDstSize, MEMF_CLEAR)))
	{
		return FALSE;
	}

	FontColumnBitsSize = (ULONG)MaxColumns * (ULONG)CharHeight;
	if (!(Font.ColumnBits = (UBYTE *)lwmf_AllocCpuMem(FontColumnBitsSize, MEMF_CLEAR)))
	{
		FreeMem(Font.ColumnDst, FontColumnDstSize);
		Font.ColumnDst = NULL;
		return FALSE;
	}

	const UBYTE *srcPlane0 = (const UBYTE *)FontBitmap->Image.Planes[0];
	const UWORD srcBPR = FontBitmap->Image.BytesPerRow;
	const UBYTE feedMask = (UBYTE)((1 << (UBYTE)Feed) - 1);
	const UBYTE srcShiftBase = (UBYTE)(8 - (UBYTE)Feed);
	UBYTE *bitsOut = Font.ColumnBits;

	for (UWORD i = 0; i < TextLength; ++i)
	{
		const UBYTE c = (UBYTE)Text[i];
		const WORD MapVal = (c < 128) ? CharLookup[c] : -1;

		if (MapVal >= 0)
		{
			const WORD CharBaseX = i * CharOverallWidth;
			WORD x1 = 0;
			WORD srcx = MapVal;

			while (x1 < CharWidth)
			{
				Font.ColumnDst[Font.ColumnCount] = CharBaseX + x1;

				const UBYTE srcShift = (UBYTE)(srcShiftBase - ((UBYTE)srcx & srcShiftBase));
				const UBYTE *srcRow = srcPlane0 + ((UWORD)srcx >> 3);

				for (UBYTE r = 0; r < CharHeight; ++r)
				{
					*bitsOut++ = (*srcRow >> srcShift) & feedMask;
					srcRow += srcBPR;
				}

				++Font.ColumnCount;
				x1 += Feed;
				srcx += Feed;
			}
		}
	}

	lwmf_DeleteImage(FontBitmap);

	return TRUE;
}

static void Draw_SineScroller(UBYTE Buffer)
{
	const WORD ScrollX = Font.ScrollX;
	const WORD LeftVisibleTextX = -ScrollX;
	const WORD RightVisibleTextX = (SCREENWIDTH - SCROLLER_FEED) - ScrollX;

	UBYTE *DstPlane = (UBYTE *)ScreenBitmap[Buffer]->Planes[0];

	const WORD *ColumnDst = Font.ColumnDst;
	const WORD *DstEnd = ColumnDst + Font.ColumnCount;

	const WORD *dstPtr = ColumnDst + Font.FirstVisibleColumn;
	UBYTE *bitsPtr = Font.ColumnBits + (UWORD)Font.FirstVisibleColumn * SCROLLER_CHAR_HEIGHT;

	while (dstPtr < DstEnd && *dstPtr < LeftVisibleTextX)
	{
		++dstPtr;
		bitsPtr += SCROLLER_CHAR_HEIGHT;
	}

	Font.FirstVisibleColumn = (UWORD)(dstPtr - ColumnDst);

	while (dstPtr < DstEnd)
	{
		const WORD dstTextX = *dstPtr;

		if (dstTextX >= RightVisibleTextX)
		{
			break;
		}

		const WORD dstX = ScrollX + dstTextX;
		const UBYTE *shiftLUT = ScrollShiftLUT[((UBYTE)dstX & 6) >> 1];

		UBYTE *dst = DstPlane + ScrollRowOffset[(UWORD)dstX];

		*dst |= shiftLUT[*bitsPtr++];
		dst += INTERLEAVED_STRIDE;

		*dst |= shiftLUT[*bitsPtr++];
		dst += INTERLEAVED_STRIDE;

		*dst |= shiftLUT[*bitsPtr++];
		dst += INTERLEAVED_STRIDE;

		*dst |= shiftLUT[*bitsPtr++];
		dst += INTERLEAVED_STRIDE;

		*dst |= shiftLUT[*bitsPtr++];
		dst += INTERLEAVED_STRIDE;

		*dst |= shiftLUT[*bitsPtr++];
		dst += INTERLEAVED_STRIDE;

		*dst |= shiftLUT[*bitsPtr++];
		dst += INTERLEAVED_STRIDE;

		*dst |= shiftLUT[*bitsPtr++];
		dst += INTERLEAVED_STRIDE;

		*dst |= shiftLUT[*bitsPtr++];
		dst += INTERLEAVED_STRIDE;

		*dst |= shiftLUT[*bitsPtr++];
		dst += INTERLEAVED_STRIDE;

		*dst |= shiftLUT[*bitsPtr++];
		dst += INTERLEAVED_STRIDE;

		*dst |= shiftLUT[*bitsPtr++];
		dst += INTERLEAVED_STRIDE;

		*dst |= shiftLUT[*bitsPtr++];
		dst += INTERLEAVED_STRIDE;

		*dst |= shiftLUT[*bitsPtr++];
		dst += INTERLEAVED_STRIDE;

		*dst |= shiftLUT[*bitsPtr++];
		dst += INTERLEAVED_STRIDE;

		*dst |= shiftLUT[*bitsPtr++];
		dst += INTERLEAVED_STRIDE;

		*dst |= shiftLUT[*bitsPtr++];
		dst += INTERLEAVED_STRIDE;

		*dst |= shiftLUT[*bitsPtr++];
		dst += INTERLEAVED_STRIDE;

		*dst |= shiftLUT[*bitsPtr++];
		dst += INTERLEAVED_STRIDE;

		*dst |= shiftLUT[*bitsPtr++];
		dst += INTERLEAVED_STRIDE;

		++dstPtr;
	}

	Font.ScrollX -= (SCROLLER_FEED << 1);

	if (Font.ScrollX < -Font.Length)
	{
		Font.ScrollX = SCREENWIDTH;
		Font.FirstVisibleColumn = 0;
	}
}

static void Cleanup_SineScroller(void)
{
	if (RainbowTab)
	{
		FreeMem(RainbowTab, RainbowTabSize);
		RainbowTab = NULL;
		RainbowTabDim = NULL;
	}

	if (ScrollRowOffset)
	{
		FreeMem(ScrollRowOffset, ScrollRowOffsetSize);
		ScrollRowOffset = NULL;
	}

	if (Font.ColumnDst)
	{
		FreeMem(Font.ColumnDst, FontColumnDstSize);
		Font.ColumnDst = NULL;
	}

	if (Font.ColumnBits)
	{
		FreeMem(Font.ColumnBits, FontColumnBitsSize);
		Font.ColumnBits = NULL;
	}
}

// =====================================================================
// Copper
// =====================================================================

static UWORD *CopperList = NULL;
static ULONG CopperListSize = 0;
static UWORD PlasmaStart = 0;
static UWORD PlasmaColorLUT[512];
static UBYTE PlasmaPhaseLUT[256];

static UWORD BPL1PTH_Idx = 0;
static UWORD BPL1PTL_Idx = 0;
static UWORD BPL2PTH_Idx = 0;
static UWORD BPL2PTL_Idx = 0;
static UWORD BPL3PTH_Idx = 0;
static UWORD BPL3PTL_Idx = 0;

static UWORD ScrollBPL1PTH_Idx = 0;
static UWORD ScrollBPL1PTL_Idx = 0;
static UWORD ScrollBPL2PTH_Idx = 0;
static UWORD ScrollBPL2PTL_Idx = 0;

#define WHITE_LINE_1 84
#define PLASMA_START_LINE 85
#define PLASMA_LINES 86
#define WHITE_LINE_2 171
#define SCROLLER_START_LINE 172
#define SCROLLER_LINES (SCREENHEIGHT - WHITE_LINE_2 - 1)

static UWORD *ScrollRainbowColorPtr[SCROLLER_LINES];
static UBYTE RainbowPhase = 0;

#define PLASMA_COLS 40
#define PLASMA_COLS_PER_BLOCK 8
#define PLASMA_BLOCKS (PLASMA_COLS / PLASMA_COLS_PER_BLOCK)
#define LINE_WORDS (2 + 2 + 2 * PLASMA_COLS + 2)

// Modulo to add to BPLxPT after each row in an interleaved bitmap (skips the other planes)
#define INTERLEAVEDMOD (BYTESPERROW * (NUMBEROFBITPLANES - 1))

// VPOS offset for PAL display (first visible Line = $2C = 44)
#define VPOS_OFFSET 0x2C

// VPOS helpers
#define WHITE1_VPOS (VPOS_OFFSET + WHITE_LINE_1)
#define PLASMA_VPOS_START (VPOS_OFFSET + PLASMA_START_LINE)
#define WHITE2_VPOS (VPOS_OFFSET + WHITE_LINE_2)
#define SCROLLER_VPOS_START (VPOS_OFFSET + SCROLLER_START_LINE)
#define SCROLLER_BPLPOINTER SCROLLER_START_LINE * BYTESPERROW * NUMBEROFBITPLANES

// Shadow effect parameters for the sine scroller
// BPL2 = same data as BPL1, shifted SHADOW_DX pixels right and SHADOW_DY lines down via Copper
#define SHADOW_DX 3
#define SHADOW_DY 3
#define SHADOW_COLOR 0x246
#define SCROLLER_TEXT_COLOR 0xC0D

// Mirror effect: reflects the scroller region starting at SCROLLER_MIRROR_LINE
// BPLxMOD is set negative so the hardware reads bitplane rows in reverse order
#define SCROLLER_MIRROR_LINE 228
#define MIRROR_TEXT_COLOR 0x508	  // dimmer magenta (reflected text)
#define MIRROR_SHADOW_COLOR 0x125 // dark blue-purple (reflected shadow)

typedef struct
{
	UWORD Line;
	UWORD Color;
} SKYKEY;

static const SKYKEY SkyKeys[] =
	{
		// Line, RGB4 Color
		{0, 0x012},	  // very dark blue
		{28, 0x124},  // blue-violet
		{56, 0x336},  // purple
		{84, 0x648},  // warm purple
		{112, 0xA63}, // sunrise orange
		{140, 0xD95}, // bright peach
		{168, 0xCB8}, // pale warm sky
		{196, 0x9BD}, // light cyan
		{224, 0x8CF}, // bright sky blue
		{255, 0xBDF}  // pale morning blue
};

static UWORD SkyColorForLine(UWORD y)
{
	// SkyKeys span [0..255] exactly — y always matches a segment
	for (UWORD i = 0; i < (sizeof(SkyKeys) / sizeof(SkyKeys[0])) - 1; ++i)
	{
		const UWORD p0 = SkyKeys[i].Line;
		const UWORD p1 = SkyKeys[i + 1].Line;

		if (y >= p0 && y <= p1)
		{
			return lwmf_RGBLerp(SkyKeys[i].Color, SkyKeys[i + 1].Color, y - p0, p1 - p0);
		}
	}

	return SkyKeys[(sizeof(SkyKeys) / sizeof(SkyKeys[0])) - 1].Color;
}

static void AddSkyLine(UWORD **Copperlist, UWORD y)
{
	const UWORD VPOS = VPOS_OFFSET + y;

	// VPOS wrap at 256
	if (VPOS == 256)
	{
		*(*Copperlist)++ = 0xFFDF;
		*(*Copperlist)++ = 0xFFFE;
	}

	*(*Copperlist)++ = ((VPOS & 0xFF) << 8) | 0x07;
	*(*Copperlist)++ = 0xFFFE;
	*(*Copperlist)++ = 0x180;
	*(*Copperlist)++ = SkyColorForLine(y);
}

// Copper list size:
// Header: 106 words (DIWSTRT+DIWSTOP+DDFSTRT+DDFSTOP=8, AGA cleanup=6, BPLCON0..2+MODs=10, BPL1..3 PTH/PTL=12,
//                   COLOR00..07=16, section WAITs/MOVEs=36, footer VPOS-wrap+END=4, scroller colors=6, BPL pointers=6, BPLCON1 scroll=2)
#define COPPERWORDS 106
#define SKY_LINES (WHITE_LINE_1 + SCROLLER_LINES)
// Shadow is now handled entirely via BPL2 pointer offset — no extra Copper words needed.
#define SHADOW_COPPER_WORDS 0
// Extra Copper words for mirror MOD/color adjustments within the scroller sky loop
// MIRROR_LINE-1: BPL1MOD + BPL2MOD = 4; MIRROR_LINE: BPLCON1 + BPL1MOD + BPL2MOD + COLOR01..03 = 12
#define MIRROR_COPPER_WORDS 16
#define RAINBOW_COPPER_WORDS (SCROLLER_LINES * 4)

static BOOL Init_CopperList(void)
{
	const ULONG CopperListLength = COPPERWORDS + (PLASMA_LINES * LINE_WORDS) + (SKY_LINES * 4 + 2) + SHADOW_COPPER_WORDS + MIRROR_COPPER_WORDS + RAINBOW_COPPER_WORDS;

	CopperListSize = CopperListLength * sizeof(UWORD);

	if (!(CopperList = (UWORD *)AllocMem(CopperListSize, MEMF_CHIP | MEMF_CLEAR)))
	{
		return FALSE;
	}

	UWORD Index = 0;

	// Display window top/left (PAL DIWSTRT)
	CopperList[Index++] = 0x8E;
	CopperList[Index++] = 0x2C81;

	// Display window bottom/right (PAL DIWSTOP)
	CopperList[Index++] = 0x90;
	CopperList[Index++] = 0x2CC1;

	// DDFSTRT
	CopperList[Index++] = 0x92;
	CopperList[Index++] = 0x0038;

	// DDFSTOP
	CopperList[Index++] = 0x94;
	CopperList[Index++] = 0x00D0;

	// AGA cleanup: force OCS/ECS compatible fetch and default color bank
	CopperList[Index++] = 0x106;
	CopperList[Index++] = 0x0000;
	CopperList[Index++] = 0x10C;
	CopperList[Index++] = 0x0000;
	CopperList[Index++] = 0x1FC;
	CopperList[Index++] = 0x0000;

	// BPLCON0 - 3 bitplanes + Color (logo region)
	CopperList[Index++] = 0x100;
	CopperList[Index++] = 0x3200;

	// BPLCON1
	CopperList[Index++] = 0x102;
	CopperList[Index++] = 0x0000;

	// BPLCON2
	CopperList[Index++] = 0x104;
	CopperList[Index++] = 0x0000;

	// BPL1MOD (interleaved: skip over other planes' rows)
	CopperList[Index++] = 0x108;
	CopperList[Index++] = INTERLEAVEDMOD;

	// BPL2MOD
	CopperList[Index++] = 0x10A;
	CopperList[Index++] = INTERLEAVEDMOD;

	// BPL1PTH/PTL (updated each frame)
	CopperList[Index++] = 0x0E0;
	BPL1PTH_Idx = Index;
	CopperList[Index++] = 0x0000;

	CopperList[Index++] = 0x0E2;
	BPL1PTL_Idx = Index;
	CopperList[Index++] = 0x0000;

	// BPL2PTH/PTL
	CopperList[Index++] = 0x0E4;
	BPL2PTH_Idx = Index;
	CopperList[Index++] = 0x0000;

	CopperList[Index++] = 0x0E6;
	BPL2PTL_Idx = Index;
	CopperList[Index++] = 0x0000;

	// BPL3PTH/PTL
	CopperList[Index++] = 0x0E8;
	BPL3PTH_Idx = Index;
	CopperList[Index++] = 0x0000;

	CopperList[Index++] = 0x0EA;
	BPL3PTL_Idx = Index;
	CopperList[Index++] = 0x0000;

	// COLOR00-COLOR07 (logo palette)
	for (UBYTE c = 0; c < 8; ++c)
	{
		CopperList[Index++] = 0x180 + c * 2;
		CopperList[Index++] = LogoPalette[c];
	}

	// Copper sky in logo region
	UWORD *Copperlist = &CopperList[Index];

	for (UWORD y = 0; y < WHITE_LINE_1; ++y)
	{
		AddSkyLine(&Copperlist, y);
	}

	Index = (UWORD)(Copperlist - CopperList);

	// --- White Line 1 (between logo and plasma) ---
	CopperList[Index++] = (WHITE1_VPOS << 8) | 0x07;
	CopperList[Index++] = 0xFFFE;
	CopperList[Index++] = 0x180;
	CopperList[Index++] = 0xFFF;

	// Switch to 0 bitplanes for plasma (copper-only colors)
	CopperList[Index++] = (PLASMA_VPOS_START << 8) | 0x07;
	CopperList[Index++] = 0xFFFE;
	CopperList[Index++] = 0x100;
	CopperList[Index++] = 0x0200;
	CopperList[Index++] = 0x180;
	CopperList[Index++] = 0x000;

	// --- Per-scanline plasma region ---
	PlasmaStart = Index;

	for (UWORD i = 0; i < PLASMA_LINES; ++i)
	{
		// Pre-Color: set COLOR00 before WAIT
		CopperList[Index++] = 0x180;
		CopperList[Index++] = 0x000;

		// WAIT with 4px dithering between even/odd lines
		UWORD h = (i & 1) ? 0x41 : 0x3F;
		CopperList[Index++] = ((PLASMA_VPOS_START + i) << 8) | h;
		CopperList[Index++] = 0xFFFE;

		for (UWORD j = 0; j < PLASMA_COLS; ++j)
		{
			CopperList[Index++] = 0x180;
			CopperList[Index++] = 0x000;
		}

		// End-of-Line WAIT
		CopperList[Index++] = ((PLASMA_VPOS_START + i) << 8) | 0xDF;
		CopperList[Index++] = 0xFFFE;
	}

	// --- White Line 2 (between plasma and scroller) ---
	CopperList[Index++] = (WHITE2_VPOS << 8) | 0x07;
	CopperList[Index++] = 0xFFFE;
	CopperList[Index++] = 0x180;
	CopperList[Index++] = 0xFFF;

	// Preload first sky Color for the Line BELOW white Line 2
	CopperList[Index++] = (WHITE2_VPOS << 8) | 0xE3;
	CopperList[Index++] = 0xFFFE;
	CopperList[Index++] = 0x180;
	CopperList[Index++] = SkyColorForLine(WHITE_LINE_2 + 1);

	// BPLCON0 Switch to 2 bitplanes for scroller (BPL1=text, BPL2=shadow)
	CopperList[Index++] = (SCROLLER_VPOS_START << 8) | 0x07;
	CopperList[Index++] = 0xFFFE;
	CopperList[Index++] = 0x100;
	CopperList[Index++] = 0x2200;

	// BPL1PTH/PTL (text plane)
	CopperList[Index++] = 0x0E0;
	ScrollBPL1PTH_Idx = Index;
	CopperList[Index++] = 0x0000;

	CopperList[Index++] = 0x0E2;
	ScrollBPL1PTL_Idx = Index;
	CopperList[Index++] = 0x0000;

	// BPL2PTH/PTL (shadow plane — same data as BPL1, offset via Copper)
	CopperList[Index++] = 0x0E4;
	ScrollBPL2PTH_Idx = Index;
	CopperList[Index++] = 0x0000;

	CopperList[Index++] = 0x0E6;
	ScrollBPL2PTL_Idx = Index;
	CopperList[Index++] = 0x0000;

	// COLOR00 = sky (set per-line by AddSkyLine)
	// COLOR01 = text only (BPL1=1, BPL2=0)
	// COLOR02 = shadow only (BPL1=0, BPL2=1)
	// COLOR03 = text+shadow overlap (BPL1=1, BPL2=1) — same as text color
	CopperList[Index++] = 0x182;
	CopperList[Index++] = SCROLLER_TEXT_COLOR;
	CopperList[Index++] = 0x184;
	CopperList[Index++] = SHADOW_COLOR;
	CopperList[Index++] = 0x186;
	CopperList[Index++] = SCROLLER_TEXT_COLOR;

	// BPLCON1: horizontal pixel shift for BPL2 (shadow), active for the whole scroller region.
	// Reset to 0 at SCROLLER_MIRROR_LINE to remove shadow in the reflection.
	CopperList[Index++] = 0x102;
	CopperList[Index++] = (UWORD)(SHADOW_DX << 4);

	// Copper sky behind scroller (mirror lines set BPLxMOD for reverse scan)
	Copperlist = &CopperList[Index];

	for (UWORD y = WHITE_LINE_2 + 1; y < SCREENHEIGHT; ++y)
	{
		AddSkyLine(&Copperlist, y);

		// Per-line rainbow: MOVE COLOR01 + MOVE COLOR03; store direct pointer to the COLOR01 value slot
		*Copperlist++ = 0x182;
		ScrollRainbowColorPtr[y - (WHITE_LINE_2 + 1)] = Copperlist;
		*Copperlist++ = SCROLLER_TEXT_COLOR;
		*Copperlist++ = 0x186;
		*Copperlist++ = SCROLLER_TEXT_COLOR;

		if (y == SCROLLER_MIRROR_LINE - 1)
		{
			// Repeat this line at MIRROR_LINE so the reflection starts from the same row
			*Copperlist++ = 0x108;
			*Copperlist++ = (UWORD)(-(BYTESPERROW));
			*Copperlist++ = 0x10A;
			*Copperlist++ = (UWORD)(-(BYTESPERROW));
		}
		else if (y == SCROLLER_MIRROR_LINE)
		{
			// Scan backwards: after each row (40 bytes read), step back one full interleaved row
			// MOD = -(BYTESPERROW + INTERLEAVED_STRIDE) = -(40+120) = -160
			*Copperlist++ = 0x102;
			*Copperlist++ = 0x0000; // reset BPLCON1 (remove horizontal shadow shift)
			*Copperlist++ = 0x108;
			*Copperlist++ = (UWORD)(-(BYTESPERROW + INTERLEAVED_STRIDE));
			*Copperlist++ = 0x10A;
			*Copperlist++ = (UWORD)(-(BYTESPERROW + INTERLEAVED_STRIDE));
			// Mirror palette: dimmer colors to simulate water reflection
			*Copperlist++ = 0x182;
			*Copperlist++ = MIRROR_TEXT_COLOR;
			*Copperlist++ = 0x184;
			*Copperlist++ = MIRROR_SHADOW_COLOR;
			*Copperlist++ = 0x186;
			*Copperlist++ = MIRROR_TEXT_COLOR;
		}
	}

	Index = (UWORD)(Copperlist - CopperList);

	// VPOS wrap for lines > 255
	CopperList[Index++] = 0xFFDF;
	CopperList[Index++] = 0xFFFE;

	// Copper list end
	CopperList[Index++] = 0xFFFF;
	CopperList[Index++] = 0xFFFE;

	return TRUE;
}

static void Update_BitplanePointers(UBYTE Buffer)
{
	// Each pointer gets its own high word calculated independently.
	// The buffer may straddle a 64K boundary (AllocMem gives no alignment guarantee),
	const ULONG Base = (ULONG)ScreenBitmap[Buffer]->Planes[0];

	// Logo region: 3 bitplane pointers
	CopperList[BPL1PTH_Idx] = (UWORD)(Base >> 16);
	CopperList[BPL1PTL_Idx] = (UWORD)Base;

	const ULONG Bpl2Addr = Base + BYTESPERROW;
	CopperList[BPL2PTH_Idx] = (UWORD)(Bpl2Addr >> 16);
	CopperList[BPL2PTL_Idx] = (UWORD)Bpl2Addr;

	const ULONG Bpl3Addr = Base + 2 * BYTESPERROW;
	CopperList[BPL3PTH_Idx] = (UWORD)(Bpl3Addr >> 16);
	CopperList[BPL3PTL_Idx] = (UWORD)Bpl3Addr;

	// Scroller region
	const ULONG ScrollAddr = Base + SCROLLER_BPLPOINTER;
	CopperList[ScrollBPL1PTH_Idx] = (UWORD)(ScrollAddr >> 16);
	CopperList[ScrollBPL1PTL_Idx] = (UWORD)ScrollAddr;

	// BPL2 (shadow) starts SHADOW_DY bitmap rows behind BPL1 (lower address = earlier row).
	const ULONG ShadowAddr = ScrollAddr - (ULONG)SHADOW_DY * INTERLEAVED_STRIDE;
	CopperList[ScrollBPL2PTH_Idx] = (UWORD)(ShadowAddr >> 16);
	CopperList[ScrollBPL2PTL_Idx] = (UWORD)ShadowAddr;
}

// Update per-line COLOR01 and COLOR03 in the Copper list every frame.
// Uses precomputed RainbowTab[256] and direct UWORD* pointers for minimal overhead.
// Two separate loops avoid a per-iteration branch on the mirror threshold.
static void Update_ScrollerRainbow(void)
{
	const UWORD MirrorStart = SCROLLER_MIRROR_LINE - SCROLLER_START_LINE;
	UBYTE idx = RainbowPhase;

	for (UWORD i = 0; i < MirrorStart; ++i)
	{
		const UWORD c = RainbowTab[idx];
		UWORD *p = ScrollRainbowColorPtr[i];
		p[0] = c;
		p[2] = c;
		idx += 3;
	}

	// Mirror region: half-brightness to simulate water reflection
	for (UWORD i = MirrorStart; i < SCROLLER_LINES; ++i)
	{
		const UWORD c = RainbowTabDim[idx];
		UWORD *p = ScrollRainbowColorPtr[i];
		p[0] = c;
		p[2] = c;
		idx += 3;
	}

	++RainbowPhase;
}

// =====================================================================
// Plasma
// =====================================================================

static void Init_Plasma(void)
{
	const UBYTE CompBase[64] =
		{
			8, 8, 9, 10, 10, 11, 12, 12, 13, 13, 14, 14, 14, 15, 15, 15, 15, 15, 15, 15, 14, 14, 14, 13, 13, 12, 12, 11, 10, 10, 9, 8,
			8, 7, 6, 5, 5, 4, 3, 3, 2, 2, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 2, 2, 3, 3, 4, 5, 5, 6, 7};

	for (UWORD i = 0; i < 512; ++i)
	{
		const UWORD p = i & 255;
		const UBYTE r = CompBase[p & 63];
		const UBYTE g = CompBase[(p + 43) & 63];
		const UBYTE b = CompBase[(p + 85) & 63];

		PlasmaColorLUT[i] = (UWORD)((r << 8) | (g << 4) | b);
	}

	for (UWORD i = 0; i < 256; ++i)
	{
		PlasmaPhaseLUT[i] = (UBYTE)(SinTab256[i] + SinTab256[(UBYTE)(i + 90)]);
	}
}

static void Update_Plasma(void)
{
	static UBYTE Phase1 = 0;
	// Interlaced row update: process only even or odd rows per frame.
	// Each row is refreshed at 25 Hz instead of 50 Hz, halving the number of
	// Chip RAM writes per frame (~43 rows instead of 85 = 50% less bus traffic).
	// Only COLOR00 value words are written; Copper register words stay static.
	static UBYTE RowToggle = 0;

	// Start p at the phase that corresponds to the first processed row
	// (RowToggle=0 -> row 0, RowToggle=1 -> row 1); since p = Phase1 + row
	// in both cases this keeps the per-row color identical to the original.
	UBYTE p = Phase1 + RowToggle;
	UWORD *lineBase = &CopperList[PlasmaStart] + RowToggle * LINE_WORDS;

	for (UWORD row = RowToggle; row < PLASMA_LINES; row += 2)
	{
		const UWORD Phase2 = PlasmaPhaseLUT[p] + Phase1;
		const UWORD *src = PlasmaColorLUT + Phase2;
		UWORD *dst = lineBase + 5;

		// Pre-WAIT COLOR00 value slot
		lineBase[1] = *src++;

		for (UWORD j = 0; j < PLASMA_BLOCKS; ++j)
		{
			*dst = *src++;
			dst += 2;
			*dst = *src++;
			dst += 2;
			*dst = *src++;
			dst += 2;
			*dst = *src++;
			dst += 2;
			*dst = *src++;
			dst += 2;
			*dst = *src++;
			dst += 2;
			*dst = *src++;
			dst += 2;
			*dst = *src++;
			dst += 2;
		}

		p += 2;
		lineBase += 2 * LINE_WORDS;
	}

	RowToggle ^= 1;
	++Phase1;
}

// =====================================================================
// Cleanup & Main
// =====================================================================

static void Cleanup_All(void)
{
	Cleanup_SineScroller();
	Cleanup_TextLogo();

	lwmf_CleanupModPlayer(&MOD_Demosong);

	if (CopperList)
	{
		FreeMem(CopperList, CopperListSize);
	}

	lwmf_CleanupScreenBitmaps();

	lwmf_CleanupAll();
}

int main()
{
	if (lwmf_LoadGraphicsLib() != 0)
	{
		return 20;
	}

	extern UBYTE ModMusic[];
	extern UBYTE ModMusic_end[];

	if (!lwmf_InitModPlayerMem(&MOD_Demosong, ModMusic, (ULONG)(ModMusic_end - ModMusic)))
	{
		Cleanup_All();
		return 20;
	}

	if (!lwmf_InitScreenBitmaps())
	{
		Cleanup_All();
		return 20;
	}

	if (!Init_TextLogo())
	{
		Cleanup_All();
		return 20;
	}

	if (!Init_SineScroller())
	{
		Cleanup_All();
		return 20;
	}

	if (!Init_CopperList())
	{
		Cleanup_All();
		return 20;
	}

	Init_Plasma();

	UBYTE CurrentBuffer = 1;
	Update_BitplanePointers(0);

	lwmf_TakeOverOS();
	*COP1LC = (ULONG)CopperList;

	// mt_install must happen AFTER TakeOverOS so ptplayer sets its INTENA bit
	// after the OS interrupt handlers have been disabled — not before.
	lwmf_InstallModPlayer(&MOD_Demosong);

	lwmf_StartMODPlayer(&MOD_Demosong);

	while (*CIAA_PRA & 0x40)
	{
		BlitClearPlane0Lines(SCROLLER_CLEAR_START, SCROLLER_CLEAR_LINES, (UBYTE *)ScreenBitmap[CurrentBuffer]->Planes[0]);
		BlitClearTextLogoOld(CurrentBuffer);

		Draw_SineScroller(CurrentBuffer);
		Draw_TextLogo(CurrentBuffer);

		// Wait for vertical blank before modifying the Copper list.
		// All writes happen here in the blanking interval where bitplane DMA is
		// inactive, giving full Chip RAM bandwidth and no Copper conflicts.
		lwmf_WaitVertBlank();

		Update_BitplanePointers(CurrentBuffer);
		Update_Plasma();
		Update_ScrollerRainbow();

		CurrentBuffer ^= 1;
	}

	lwmf_StopMODPlayer(&MOD_Demosong);

	Cleanup_All();
	return 0;
}
