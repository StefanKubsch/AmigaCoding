//**********************************************************************
//* Amiga 1200 Intro                                                   *
//* Will run on Amiga 500, but very slow                               *
//*                                                                    *
//* (C) 2020-2026 by Stefan Kubsch                                     *
//* Project for vbcc                                                   *
//*                                                                    *
//* Compile & link with:                                               *
//* make_A1200-Intro.cmd                                               *
//*                                                                    *
//* Quit with mouse click                                              *
//**********************************************************************

#include "lwmf/lwmf.h"

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
// Bouncing Text Logo
// =====================================================================

static struct lwmf_Image* LogoBitmap = NULL;

static const UWORD LogoPalette[8] = {0x003, 0x368, 0x134, 0x012, 0x246,	0x146, 0x123, 0x001};

#define LOGO_WIDTH  192
#define LOGO_HEIGHT 46

// Lissajous X table: center=64, amplitude=60, range 4-124
static const UBYTE LogoSinTabX[64] =
{
	64,70,76,82,87,93,98,103,107,111,114,117,120,122,123,124,124,123,122,121,119,116,113,109,105,100,95,90,84,78,72,66,
	60,55,49,43,37,32,27,23,19,15,12,9,7,5,4,4,4,5,6,8,11,14,18,22,26,31,36,42,47,53,59,65
};

// Lissajous Y table: center=19, amplitude=18, range 1-37
// (logo region = lines 0-83, logo height 46 → max Y = 37)
static const UBYTE LogoSinTabY[64] =
{
	19,23,26,29,32,34,36,37,37,37,35,34,31,28,25,22,18,14,11,8,5,3,2,1,1,2,3,5,8,11,14,18,
	21,25,28,31,33,35,36,37,37,36,34,32,30,26,23,19,16,12,9,6,4,2,1,1,1,2,4,7,9,13,16,20
};

BOOL Init_TextLogo(void)
{
	if (!(LogoBitmap = lwmf_LoadImage("gfx/Logo.iff")))
	{
		return FALSE;
	}

	return TRUE;
}

void Draw_TextLogo(UBYTE Buffer)
{
	static UBYTE SinTabCount = 0;

	lwmf_BlitTile((long*)LogoBitmap->Image.Planes[0], 0, 0, (long*)ScreenBitmap[Buffer]->Planes[0], LogoSinTabX[SinTabCount], LogoSinTabY[SinTabCount], LOGO_WIDTH, LOGO_HEIGHT, 320);

	if (++SinTabCount >= 64)
	{
		SinTabCount = 0;
	}
}

void Cleanup_TextLogo(void)
{
	if (LogoBitmap)
	{
		lwmf_DeleteImage(LogoBitmap);
	}
}

// =====================================================================
// Sine Scroller
// =====================================================================

#define SCROLLER_FEED        2
#define SCROLLER_CHAR_HEIGHT 20
// Stride between rows in an interleaved bitmap: all 3 planes are laid out consecutively per row.
// This is independent of how many planes the Copper displays in a given screen region.
#define INTERLEAVED_STRIDE   (BYTESPERROW * NUMBEROFBITPLANES)

// Partial clear: only the bitmap regions actually DMA-fetched by the Copper need clearing.
// Logo: rows 0..WHITE_LINE_1-1 (84 lines).  Plasma has 0 bitplanes — skip.
// Scroller: BPL2 (shadow) starts SHADOW_DY rows before SCROLLER_START_LINE (row 169);
// forward display runs up to SCROLLER_MIRROR_LINE-1 (row 227), then mirror re-reads same rows.
// Total clear: 84 + 59 = 143 lines instead of 256 (−44%).
#define SCROLLER_CLEAR_START  (SCROLLER_START_LINE - SHADOW_DY)
#define SCROLLER_CLEAR_LINES  (SCROLLER_MIRROR_LINE - SCROLLER_CLEAR_START)

static struct Scrollfont
{
	UWORD Length;
	WORD  ScrollX;
	UBYTE *ColumnBits;
	WORD  *ColumnDst;
	UWORD  ColumnCount;
	UWORD  FirstVisibleColumn;
} Font;

// Precomputed per screen-X: row offset + byte offset combined.
// = (192 + sineDisp) * INTERLEAVED_STRIDE + (x >> 3)
// Eliminates one shift + add per column in the inner loop.
static UWORD *ScrollRowOffset        = NULL;
static ULONG  ScrollRowOffsetSize    = 0;
static ULONG  FontColumnDstSize      = 0;
static ULONG  FontColumnBitsSize     = 0;

// Precomputed RGB4 rainbow color table, indexed by (line*3 + phase) & 0xFF.
static UWORD *RainbowTab     = NULL;
static ULONG  RainbowTabSize = 0;

BOOL Init_SineScroller(void)
{
	struct lwmf_Image* FontBitmap;

	ScrollRowOffsetSize = sizeof(UWORD) * SCREENWIDTH;
	if (!(ScrollRowOffset = (UWORD*)lwmf_AllocCpuMem(ScrollRowOffsetSize, MEMF_CLEAR)))
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

	// Precompute RainbowTab[256]: full RGB4 color for each possible idx value.
	RainbowTabSize = sizeof(UWORD) * 256;

	if (!(RainbowTab = (UWORD*)lwmf_AllocCpuMem(RainbowTabSize, MEMF_CLEAR)))
	{
		FreeMem(ScrollRowOffset, ScrollRowOffsetSize);
		ScrollRowOffset = NULL;
		return FALSE;
	}
	for (UWORD i = 0; i < 256; ++i)
	{
		const UBYTE r = SinTab256[i]                    >> 2;
		const UBYTE g = SinTab256[(UBYTE)(i +  85u)]    >> 2;
		const UBYTE b = SinTab256[(UBYTE)(i + 170u)]    >> 2;
		RainbowTab[i] = (UWORD)((r << 8) | (g << 4) | b);
	}

	if (!(FontBitmap = lwmf_LoadImage("gfx/ScrollFont.bsh")))
	{
		FreeMem(RainbowTab, RainbowTabSize);
		RainbowTab = NULL;
		FreeMem(ScrollRowOffset, ScrollRowOffsetSize);
		ScrollRowOffset = NULL;
		return FALSE;
	}

	const char *Text           = "...WELL, WELL...NOT PERFECT, BUT STILL WORKING ON IT !!! HAVE FUN WATCHING THE DEMO AND ENJOY YOUR AMIGA !!! MUSIC - BEAMS OF LIGHT BY WALKMAN 1989...CODE AND GFX - DEEP4 2026...";
	const char *CharMap        = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!-,+?*()";
	const WORD  Feed           = SCROLLER_FEED;
	const WORD  CharWidth      = 15;
	const UBYTE CharHeight     = SCROLLER_CHAR_HEIGHT;
	const WORD  CharOverallWidth = CharWidth + 1;

	Font.ScrollX         = SCREENWIDTH;
	Font.Length          = 0;
	Font.ColumnBits      = NULL;
	Font.ColumnDst       = NULL;
	Font.ColumnCount     = 0;
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
	const UWORD MaxColumns  = TextLength * ColsPerChar;

	if (MaxColumns == 0)
	{
		return TRUE;
	}

	FontColumnDstSize = sizeof(WORD) * MaxColumns;
	if (!(Font.ColumnDst = (WORD*)lwmf_AllocCpuMem(FontColumnDstSize, MEMF_CLEAR)))
	{
		return FALSE;
	}

	FontColumnBitsSize = (ULONG)MaxColumns * (ULONG)CharHeight;
	if (!(Font.ColumnBits = (UBYTE*)lwmf_AllocCpuMem(FontColumnBitsSize, MEMF_CLEAR)))
	{
		FreeMem(Font.ColumnDst, FontColumnDstSize);
		Font.ColumnDst = NULL;
		return FALSE;
	}

	const UBYTE *srcPlane0    = (const UBYTE *)FontBitmap->Image.Planes[0];
	const UWORD  srcBPR       = FontBitmap->Image.BytesPerRow;
	const UBYTE  feedMask     = (UBYTE)((1u << (UBYTE)Feed) - 1u);
	const UBYTE  srcShiftBase = (UBYTE)(8u - (UBYTE)Feed);
	UBYTE       *bitsOut      = Font.ColumnBits;

	for (UWORD i = 0; i < TextLength; ++i)
	{
		const UBYTE c      = (UBYTE)Text[i];
		const WORD  MapVal = (c < 128) ? CharLookup[c] : -1;

		if (MapVal >= 0)
		{
			const WORD CharBaseX = i * CharOverallWidth;
			WORD x1   = 0;
			WORD srcx = MapVal;

			while (x1 < CharWidth)
			{
				Font.ColumnDst[Font.ColumnCount] = CharBaseX + x1;

				const UBYTE srcShift = (UBYTE)(srcShiftBase - ((UBYTE)srcx & srcShiftBase));
				const UBYTE *srcRow  = srcPlane0 + ((UWORD)srcx >> 3);

				for (UBYTE r = 0; r < CharHeight; ++r)
				{
					*bitsOut++ = (*srcRow >> srcShift) & feedMask;
					srcRow += srcBPR;
				}

				++Font.ColumnCount;
				x1   += Feed;
				srcx += Feed;
			}
		}
	}

	lwmf_DeleteImage(FontBitmap);

	return TRUE;
}

void Draw_SineScroller(UBYTE Buffer)
{
	const WORD  ScrollX           = Font.ScrollX;
	const WORD  LeftVisibleTextX  = -ScrollX;
	const WORD  RightVisibleTextX = (SCREENWIDTH - SCROLLER_FEED) - ScrollX;
	const UBYTE shiftBase         = (UBYTE)(8u - SCROLLER_FEED);

	UBYTE *DstPlane = (UBYTE *)ScreenBitmap[Buffer]->Planes[0];

	const WORD *ColumnDst = Font.ColumnDst;
	const WORD *DstEnd    = ColumnDst + Font.ColumnCount;

	const WORD *dstPtr  = ColumnDst + Font.FirstVisibleColumn;
	UBYTE      *bitsPtr = Font.ColumnBits + (UWORD)Font.FirstVisibleColumn * SCROLLER_CHAR_HEIGHT;

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

		const WORD  dstX     = ScrollX + dstTextX;
		const UBYTE dstShift = (UBYTE)(shiftBase - ((UBYTE)dstX & shiftBase));

		UBYTE *dst = DstPlane + ScrollRowOffset[(UWORD)dstX];

		for (WORD r = 0; r < SCROLLER_CHAR_HEIGHT; ++r)
		{
			*dst |= (UBYTE)(*bitsPtr++ << dstShift);
			dst += INTERLEAVED_STRIDE;
		}

		++dstPtr;
	}

	Font.ScrollX -= (SCROLLER_FEED << 1);

	if (Font.ScrollX < -Font.Length)
	{
		Font.ScrollX = SCREENWIDTH;
		Font.FirstVisibleColumn = 0;
	}
}

void Cleanup_SineScroller(void)
{
	if (RainbowTab)
	{
		FreeMem(RainbowTab, RainbowTabSize);
		RainbowTab = NULL;
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

static UWORD* CopperList     = NULL;
static ULONG  CopperListSize = 0;
static UWORD PlasmaStart = 0;
static ULONG PlasmaColorLUT[256];

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

// Per-line rainbow: direct pointer to each line's COLOR01 value slot in CopperList
static UWORD *ScrollRainbowColorPtr[84]; // 84 = SCREENHEIGHT - WHITE_LINE_2 - 1
static UBYTE RainbowPhase      = 0;

// Layout: 84 + 1 + 86 + 1 + 84 = 256
#define WHITE_LINE_1        84
#define PLASMA_START_LINE   85
#define PLASMA_LINES        86
#define WHITE_LINE_2        171
#define SCROLLER_START_LINE 172

#define PLASMA_COLS             40
#define PLASMA_COLS_PER_BLOCK   8
#define PLASMA_BLOCKS           (PLASMA_COLS / PLASMA_COLS_PER_BLOCK)
#define LINE_WORDS              (2 + 2 + 2 * PLASMA_COLS + 2)

// Modulo to add to BPLxPT after each row in an interleaved bitmap (skips the other planes)
#define INTERLEAVEDMOD       (BYTESPERROW * (NUMBEROFBITPLANES - 1))

// VPOS offset for PAL display (first visible Line = $2C = 44)
#define VPOS_OFFSET     		0x2C

// VPOS helpers
#define WHITE1_VPOS         	(VPOS_OFFSET + WHITE_LINE_1)
#define PLASMA_VPOS_START   	(VPOS_OFFSET + PLASMA_START_LINE)
#define WHITE2_VPOS         	(VPOS_OFFSET + WHITE_LINE_2)
#define SCROLLER_VPOS_START 	(VPOS_OFFSET + SCROLLER_START_LINE)
#define SCROLLER_BPLPOINTER		SCROLLER_START_LINE * BYTESPERROW * NUMBEROFBITPLANES

// Shadow effect parameters for the sine scroller
// BPL2 = same data as BPL1, shifted SHADOW_DX pixels right and SHADOW_DY lines down via Copper
#define SHADOW_DX              3
#define SHADOW_DY              3
#define SHADOW_COLOR           0x246
#define SCROLLER_TEXT_COLOR    0xC0D

// Mirror effect: reflects the scroller region starting at SCROLLER_MIRROR_LINE
// BPLxMOD is set negative so the hardware reads bitplane rows in reverse order
#define SCROLLER_MIRROR_LINE   228
#define MIRROR_TEXT_COLOR      0x508    // dimmer magenta (reflected text)
#define MIRROR_SHADOW_COLOR    0x125    // dark blue-purple (reflected shadow)

typedef struct
{
	UWORD Line;
	UWORD Color;
} SKYKEY;

static const SKYKEY SkyKeys[] =
{
	// Line, RGB4 Color
	{   0, 0x012 }, // very dark blue
	{  28, 0x124 }, // blue-violet
	{  56, 0x336 }, // purple
	{  84, 0x648 }, // warm purple
	{ 112, 0xA63 }, // sunrise orange
	{ 140, 0xD95 }, // bright peach
	{ 168, 0xCB8 }, // pale warm sky
	{ 196, 0x9BD }, // light cyan
	{ 224, 0x8CF }, // bright sky blue
	{ 255, 0xBDF }  // pale morning blue
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
// Header: 100 words (DIWSTRT+DIWSTOP+DDFSTRT+DDFSTOP=8, BPLCON0..2+MODs=10, BPL1..3 PTH/PTL=12,
//                   COLOR00..07=16, section WAITs/MOVEs=36, footer VPOS-wrap+END=4, scroller colors=6, BPL pointers=6, BPLCON1 scroll=2)
#define COPPERWORDS            100
// Sky: 169 lines * 4 + 2 wrap entry
#define SKY_LINES              (WHITE_LINE_1 + (SCREENHEIGHT - WHITE_LINE_2 - 1))
// Shadow is now handled entirely via BPL2 pointer offset — no extra Copper words needed.
#define SHADOW_COPPER_WORDS    0
// Extra Copper words for mirror MOD/color adjustments within the scroller sky loop
// MIRROR_LINE-1: BPL1MOD + BPL2MOD = 4; MIRROR_LINE: BPLCON1 + BPL1MOD + BPL2MOD + COLOR01..03 = 12
#define MIRROR_COPPER_WORDS    16
// Number of scanlines in the scroller region + extra Copper words for per-line COLOR01+COLOR03 rainbow
#define SCROLLER_LINES         (SCREENHEIGHT - WHITE_LINE_2 - 1) // 84
#define RAINBOW_COPPER_WORDS   (SCROLLER_LINES * 4)              // 336

BOOL Init_CopperList(void)
{
	const ULONG CopperListLength = COPPERWORDS + (PLASMA_LINES * LINE_WORDS) + (SKY_LINES * 4 + 2) + SHADOW_COPPER_WORDS + MIRROR_COPPER_WORDS + RAINBOW_COPPER_WORDS;

	CopperListSize = CopperListLength * sizeof(UWORD);

	if (!(CopperList = (UWORD*)AllocMem(CopperListSize, MEMF_CHIP | MEMF_CLEAR)))
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
			*Copperlist++ = 0x0000;            // reset BPLCON1 (remove horizontal shadow shift)
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

	*COP1LC = (ULONG)CopperList;

	return TRUE;
}

void Update_BitplanePointers(UBYTE Buffer)
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
void Update_ScrollerRainbow(void)
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
		const UWORD c = (RainbowTab[idx] >> 1) & 0x0777;
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
	// 2D RGB plasma: base table (64-entry period, doubled to 128)
	const UBYTE CompBase[128] =
	{
		8, 8, 9,10,10,11,12,12,13,13,14,14,14,15,15,15,15,15,15,15,14,14,14,13,13,12,12,11,10,10, 9, 8,
		8, 7, 6, 5, 5, 4, 3, 3, 2, 2, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 2, 2, 3, 3, 4, 5, 5, 6, 7,
		8, 8, 9,10,10,11,12,12,13,13,14,14,14,15,15,15,15,15,15,15,14,14,14,13,13,12,12,11,10,10, 9, 8,
		8, 7, 6, 5, 5, 4, 3, 3, 2, 2, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 2, 2, 3, 3, 4, 5, 5, 6, 7
	};

	for (UWORD i = 0; i < 256; ++i)
	{
		const UBYTE r = CompBase[i & 127];
		const UBYTE g = CompBase[(i + 43) & 127];
		const UBYTE b = CompBase[(i + 85) & 127];
		PlasmaColorLUT[i] = 0x01800000UL | ((ULONG)r << 8) | ((ULONG)g << 4) | b;
	}
}

void Update_Plasma(void)
{
	static UBYTE Phase1    = 0;
	// Interlaced row update: process only even or odd rows per frame.
	// Each row is refreshed at 25 Hz instead of 50 Hz, halving the number of
	// Chip RAM writes per frame (~43 rows instead of 85 = 50% less bus traffic).
	// The Phase2 value computed for each processed row is identical to the
	// non-interlaced version, so visual quality is preserved.
	static UBYTE RowToggle = 0;

	// Start p at the phase that corresponds to the first processed row
	// (RowToggle=0 → row 0, RowToggle=1 → row 1); since p = Phase1 + row
	// in both cases this keeps the per-row color identical to the original.
	UBYTE p = Phase1 + RowToggle;
	UWORD *lineBase = &CopperList[PlasmaStart] + RowToggle * LINE_WORDS;

	for (UWORD row = RowToggle; row < PLASMA_LINES; row += 2)
	{
		UBYTE Phase2 = (UBYTE)(SinTab256[p] + SinTab256[(UBYTE)(p + 90)] + Phase1);

		// Write pre-WAIT color in-place, then point lcop past pre-WAIT + WAIT (4 UWORDs = 8 bytes)
		*(ULONG *)(void *)lineBase = PlasmaColorLUT[Phase2++];
		ULONG *lcop = (ULONG *)(void *)(lineBase + 4);

		for (UWORD j = 0; j < PLASMA_BLOCKS; ++j)
		{
			*lcop++ = PlasmaColorLUT[Phase2++];
			*lcop++ = PlasmaColorLUT[Phase2++];
			*lcop++ = PlasmaColorLUT[Phase2++];
			*lcop++ = PlasmaColorLUT[Phase2++];
			*lcop++ = PlasmaColorLUT[Phase2++];
			*lcop++ = PlasmaColorLUT[Phase2++];
			*lcop++ = PlasmaColorLUT[Phase2++];
			*lcop++ = PlasmaColorLUT[Phase2++];
		}

		p         += 2;
		lineBase  += 2 * LINE_WORDS;
	}

	RowToggle ^= 1;
	++Phase1;
}

// =====================================================================
// Cleanup & Main
// =====================================================================

void Cleanup_All(void)
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

	if (!lwmf_InitModPlayer(&MOD_Demosong, "sfx/beamsoflight.mod"))
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

	lwmf_TakeOverOS();

	// mt_install must happen AFTER TakeOverOS so ptplayer sets its INTENA bit
	// after the OS interrupt handlers have been disabled — not before.
	lwmf_InstallModPlayer(&MOD_Demosong);

	lwmf_StartMODPlayer(&MOD_Demosong);

	UBYTE CurrentBuffer = 1;
	Update_BitplanePointers(0);

	while (*CIAA_PRA & 0x40)
	{
		// Partial clear: skip the plasma region (0 bitplanes, never displayed).
		// Clear scroller first (smaller = finishes sooner), then logo.
		// Draw_SineScroller (CPU) overlaps with the logo blit.
		lwmf_BlitClearLines(SCROLLER_CLEAR_START, SCROLLER_CLEAR_LINES, (long*)ScreenBitmap[CurrentBuffer]->Planes[0]);
		lwmf_BlitClearLines(0, WHITE_LINE_1, (long*)ScreenBitmap[CurrentBuffer]->Planes[0]);

		// CPU writes to scroller region (already cleared); logo blit runs in background.
		Draw_SineScroller(CurrentBuffer);
		// BlitTile waits for logo-clear to finish, then blits the logo.
		Draw_TextLogo(CurrentBuffer);

		// Wait for vertical blank before modifying the Copper list.
		// All writes happen here in the blanking interval where bitplane DMA is
		// inactive, giving full Chip RAM bandwidth and no Copper conflicts.
		lwmf_WaitVertBlank();

		Update_BitplanePointers(CurrentBuffer);
		Update_ScrollerRainbow();

		CurrentBuffer ^= 1;

		Update_Plasma();
	}

	lwmf_StopMODPlayer(&MOD_Demosong);

	Cleanup_All();
	return 0;
}
