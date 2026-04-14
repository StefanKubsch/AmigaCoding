//**********************************************************************
//* Sine Scroller effect                                               *
//* Amiga 500 OCS                                                      *
//*                                                                    *
//* (C) 2020-2026 by Stefan Kubsch                                     *
//* Project for vbcc                                                   *
//*                                                                    *
//* Compile & link with:                                               *
//* make_SineScroller.cmd                                              *
//*                                                                    *
//* Quit with mouse click                                              *
//**********************************************************************

#include "lwmf/lwmf.h"

// Assembly functions (SineScroller_vasm.s):
extern void InitScrollerBlitter(void);
extern void DrawScrollerBlit(__reg("a0") const ULONG *dataPtr, __reg("a2") const ULONG *DataEnd, __reg("a3") const UWORD *offsetTab, __reg("a4") const UBYTE *dstPlane, __reg("d0") WORD scrollX, __reg("d1") WORD rightVisX);
extern void UpdateScrollerRainbow(__reg("a0") UWORD **colorPtrTab, __reg("a1") const UWORD *rainbowTab, __reg("d0") UWORD phase, __reg("d1") UWORD totalLines);

// Enable (set to 1) for debugging
// When enabled, load per frame will be displayed via Color changing of background
#define DEBUG 				0

#if DEBUG
#define DBG_COLOR(c) (*COLOR00 = (c))
#else
#define DBG_COLOR(c) ((void)0)
#endif

// =====================================================================
// Sine table, used by the sine scroller effects
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
// Sine Scroller
// =====================================================================

// SCROLLER_FEED = 1: one pixel per column strip, required for Blitter line-mode.
// The Blitter line pattern (BLTBDAT) is 16 bits wide — one bit per row — so
// the font column must be exactly 16 pixels tall and 1 pixel wide.
#define SCROLLER_FEED        1
#define SCROLLER_CHAR_HEIGHT 16
// The Copper repeats each of the 16 bitmap rows four times, yielding 64 display lines.
#define SCROLLER_CHAR_DISPLAY   (SCROLLER_CHAR_HEIGHT * 4)
// Stride between rows in an interleaved bitmap: all 3 planes are laid out consecutively per row.
// This is independent of how many planes the Copper displays in a given screen region.
#define INTERLEAVED_STRIDE   (BYTESPERROW * NUMBEROFBITPLANES)

// Scroller position
#define SCROLLER_START_LINE     100

// Maximum sine displacement in bitmap rows: sineDisp = (s*14+16)>>5, s in [-32..31] → ±14
#define SCROLLER_SINE_AMP       14
// BPL2 starts 1 bitmap row before BPL1 (= SHADOW_DY/4), so clear must start there.
// Lowest blitter write: center(116) + SINE_AMP + 15 = 145.
// SCROLLER_CLEAR_START = 99, SCROLLER_CLEAR_LINES = 47 (vs. 158 before — 70% less blit work).
#define SCROLLER_CLEAR_START    (SCROLLER_START_LINE - (SHADOW_DY / 4))
#define SCROLLER_CLEAR_LINES    (2 * SCROLLER_CHAR_HEIGHT + SCROLLER_SINE_AMP + (SHADOW_DY / 4))

static struct Scrollfont
{
	UWORD  Length;
	WORD   ScrollX;
	ULONG *FontData;     // merged per column: hi-word = ColumnBits (pixel pattern), lo-word = ColumnDst (text X)
	UWORD  ColumnCount;
	UWORD  FirstVisibleColumn;
} Font;

// Precomputed per screen-X: byte offset of the BOTTOM row of the sine-displaced column.
// = sine_row * INTERLEAVED_STRIDE  +  15 * INTERLEAVED_STRIDE  +  word-aligned byte offset
// Collapses 3 runtime operations in Draw into a single table lookup.
static UWORD *ScrollBottomWordOffset = NULL;
static ULONG  ScrollBottomWordOffsetSize = 0;
static ULONG  FontDataSize           = 0;

// Precomputed RGB4 rainbow color table, indexed by (line*3 + phase) & 0xFF.
// RainbowTab[i] = ((SinTab256[i]>>2)<<8) | ((SinTab256[(i+85)&0xFF]>>2)<<4) | (SinTab256[(i+170)&0xFF]>>2)
// Constant (phase-independent): only the starting index changes each frame.
static UWORD *RainbowTab     = NULL;
static ULONG  RainbowTabSize = 0;

BOOL Init_SineScroller(void)
{
	struct lwmf_Image* FontBitmap;

	ScrollBottomWordOffsetSize = sizeof(UWORD) * SCREENWIDTH;

	if (!(ScrollBottomWordOffset = (UWORD*)lwmf_AllocCpuMem(ScrollBottomWordOffsetSize, MEMF_CLEAR)))
	{
		return FALSE;
	}

	// Precompute RainbowTab[256]: full RGB4 color for each possible idx value.
	// Indexed as (i*3 + phase) & 0xFF, so the table is phase-independent.
	RainbowTabSize = sizeof(UWORD) * 256;

	if (!(RainbowTab = (UWORD*)lwmf_AllocCpuMem(RainbowTabSize, MEMF_CLEAR)))
	{
		FreeMem(ScrollBottomWordOffset, ScrollBottomWordOffsetSize);
		ScrollBottomWordOffset = NULL;
		return FALSE;
	}
	for (UWORD i = 0; i < 256; ++i)
	{
		const UBYTE r = SinTab256[i]                    >> 2;
		const UBYTE g = SinTab256[(UBYTE)(i +  85u)]    >> 2;
		const UBYTE b = SinTab256[(UBYTE)(i + 170u)]    >> 2;
		RainbowTab[i] = (UWORD)((r << 8) | (g << 4) | b);
	}

	// Precompute for each screen-X the byte offset of the bottom row of the sine column.
	// sine_row = SCROLLER_START_LINE + 16 + ((s*14+16)>>5);  bottom = sine_row + 15;  word_byte = (x>>3)&~1
	// SCROLLER_START_LINE + 16 = 116: the bitmap center row so that the 16px font sits
	// at rows 100..131 (display rows 100..163 after 2x doubling) and the sine displaces
	// it by ±14 display lines around the screen center.
	for (UWORD x = 0; x < SCREENWIDTH; ++x)
	{
		const WORD s = (WORD)SinTab256[(UWORD)x * 256 / SCREENWIDTH] - 32;
		ScrollBottomWordOffset[x] = (UWORD)(((SCROLLER_START_LINE + 16 + ((s * 14 + 16) >> 5)) + 15u) * INTERLEAVED_STRIDE + ((x >> 3u) & ~(UWORD)1u));
	}

	if (!(FontBitmap = lwmf_LoadImage("gfx/font16x16.ilbm")))
	{
		FreeMem(ScrollBottomWordOffset, ScrollBottomWordOffsetSize);
		ScrollBottomWordOffset = NULL;
		return FALSE;
	}

	const char *Text           = "...HERE WE GO! THIS IS A SINE SCROLLER DEMO WITH RAINBOW COLORS, WRITTEN IN C AND ASM FOR THE AMIGA 500. ENJOY THE SHOW! (C) 2026 BY DEEP4...";
	const char *CharMap        = "! #$%& ()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ ";
	const WORD  CharWidth      = 15;
	const UBYTE CharHeight     = SCROLLER_CHAR_HEIGHT;
	const WORD  CharOverallWidth = CharWidth + 1;

	Font.ScrollX         = SCREENWIDTH;
	Font.Length          = 0;
	Font.FontData        = NULL;
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

	const UWORD ColsPerChar = (UWORD)((CharWidth + SCROLLER_FEED - 1) / SCROLLER_FEED);
	const UWORD MaxColumns  = TextLength * ColsPerChar;

	if (MaxColumns == 0)
	{
		return TRUE;
	}

	// FontData is a merged array: hi-word = ColumnBits (pixel pattern), lo-word = ColumnDst (text X).
	// One ULONG read per column in the ASM inner loop instead of two separate array reads.
	FontDataSize = (ULONG)MaxColumns * sizeof(ULONG);
	if (!(Font.FontData = (ULONG*)lwmf_AllocCpuMem(FontDataSize, MEMF_CLEAR)))
	{
		return FALSE;
	}

	const UBYTE *srcPlane0 = (const UBYTE *)FontBitmap->Image.Planes[0];
	const UWORD  srcBPR    = FontBitmap->Image.BytesPerRow;

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
				// Build a 16-bit column word: row r -> bit r.
				// Bit 15 = bottom row (row 15), bit 0 = top row (row 0).
				// The Blitter draws upward (octant 1) starting from the bottom:
				// first step uses bit 15 (BSH=15), each subsequent step shifts down by 1.
				const UBYTE  bitIdx  = (UBYTE)(7u - ((UBYTE)srcx & 7u));
				const UBYTE *srcRow  = srcPlane0 + ((UWORD)srcx >> 3);
				UWORD        colWord = 0;

				for (UBYTE r = 0; r < CharHeight; ++r)
				{
					if (*srcRow & (1u << bitIdx))
					{
						colWord |= (UWORD)(1u << r);  // row r -> bit r
					}
					srcRow += srcBPR;
				}

				// Skip blank columns (no pixels) — avoids pointless blits at runtime.
				if (colWord != 0)
				{
					// Pack: hi-word = ColumnBits, lo-word = ColumnDst
					Font.FontData[Font.ColumnCount] = ((ULONG)colWord << 16) | (UWORD)(CharBaseX + x1);
					++Font.ColumnCount;
				}
				x1   += SCROLLER_FEED;
				srcx += SCROLLER_FEED;
			}
		}
	}

	InitScrollerBlitter();
	lwmf_DeleteImage(FontBitmap);

	return TRUE;
}

void Draw_SineScroller(UBYTE Buffer)
{
	const WORD ScrollX           = Font.ScrollX;
	const WORD LeftVisibleTextX  = -ScrollX;
	const WORD RightVisibleTextX = (SCREENWIDTH - SCROLLER_FEED) - ScrollX;

	const UBYTE *DstPlane = (const UBYTE *)ScreenBitmap[Buffer]->Planes[0];

	const ULONG *FontData  = Font.FontData;
	const ULONG *DataEnd   = FontData + Font.ColumnCount;
	const ULONG *dataPtr   = FontData + Font.FirstVisibleColumn;

	// Skip columns that have already scrolled off the left edge.
	// lo-word of each entry is ColumnDst; cast to WORD for signed comparison.
	while (dataPtr < DataEnd && (WORD)*dataPtr < LeftVisibleTextX)
	{
		++dataPtr;
	}

	Font.FirstVisibleColumn = (UWORD)(dataPtr - FontData);

	DBG_COLOR(0xF00);          /* red = hotloop */
	DrawScrollerBlit(dataPtr, DataEnd, ScrollBottomWordOffset, DstPlane, ScrollX, RightVisibleTextX);
	DBG_COLOR(0x000);          /* end of hotloop bar */

	Font.ScrollX -= 2;  // scroll 2 pixels per frame

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

	if (ScrollBottomWordOffset)
	{
		FreeMem(ScrollBottomWordOffset, ScrollBottomWordOffsetSize);
		ScrollBottomWordOffset = NULL;
	}

	if (Font.FontData)
	{
		FreeMem(Font.FontData, FontDataSize);
		Font.FontData = NULL;
	}
}

// =====================================================================
// Copper
// =====================================================================

static UWORD* CopperList     = NULL;
static ULONG  CopperListSize = 0;

static UWORD ScrollBPL1PTH_Idx = 0;
static UWORD ScrollBPL1PTL_Idx = 0;
static UWORD ScrollBPL2PTH_Idx = 0;
static UWORD ScrollBPL2PTL_Idx = 0;

// Modulo to add to BPLxPT after each row in an interleaved bitmap (skips the other planes)
#define INTERLEAVEDMOD          (BYTESPERROW * (NUMBEROFBITPLANES - 1))

// VPOS offset for PAL display (first visible Line = $2C = 44)
#define VPOS_OFFSET     		0x2C

// VPOS helpers
#define SCROLLER_LINES          (SCREENHEIGHT - SCROLLER_START_LINE)
#define SCROLLER_VPOS_START 	(VPOS_OFFSET + SCROLLER_START_LINE)
#define SCROLLER_BPLPOINTER		SCROLLER_START_LINE * BYTESPERROW * NUMBEROFBITPLANES

// Per-line rainbow: direct pointer to each line's COLOR01 value slot in CopperList
static UWORD *ScrollRainbowColorPtr[SCROLLER_LINES];
static UBYTE RainbowPhase = 0;

// Shadow effect parameters for the sine scroller
// BPL2 = same data as BPL1, shifted SHADOW_DX pixels right and SHADOW_DY display lines down via Copper.
// SHADOW_DY must be even so that the pull-back falls on an odd display line (post-advance BPL2 state).
#define SHADOW_DX              3
#define SHADOW_DY              4
#define SHADOW_COLOR           0x246
#define SCROLLER_TEXT_COLOR    0xC0D

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
// Fixed header: DIWSTRT+DIWSTOP+DDFSTRT+DDFSTOP+BPLCON0+COLOR00+BPL1MOD+BPL2MOD=16,
//               scroller init (WAIT+BPLCON0+BPL1/2 PTH/PTL+COLOR01..03+BPLCON1)=20, END=2 => 38 words
#define COPPERWORDS            38
// Per-row 4x-stretch: both BPL1MOD and BPL2MOD for 64 display lines.
// = 64 display lines * 2 registers * 2 words = 256 extra words
#define DOUBLE_COPPER_WORDS    (SCROLLER_CHAR_HEIGHT * 16)
// Number of scanlines in the scroller (lower sky) region, used for per-line rainbow
#define RAINBOW_COPPER_WORDS   (SCROLLER_LINES * 4)

BOOL Init_CopperList(void)
{
	const ULONG CopperListLength = COPPERWORDS + (SCROLLER_START_LINE * 4) + (SCROLLER_LINES * 4 + 2) + DOUBLE_COPPER_WORDS + RAINBOW_COPPER_WORDS;

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

	// BPLCON0 - 0 bitplanes
	CopperList[Index++] = 0x100;
	CopperList[Index++] = 0x0200;

	// Pre-set COLOR00 immediately (no WAIT) to black.
	// Keeps the top border (VPOS 0-43, before the first sky WAIT at line 44) black
	// instead of leaking the sky start color or the previous frame's bottom-sky color.
	CopperList[Index++] = 0x180;
	CopperList[Index++] = 0x000;

	// BPL1MOD (interleaved: skip over other planes' rows)
	CopperList[Index++] = 0x108;
	CopperList[Index++] = INTERLEAVEDMOD;

	// BPL2MOD
	CopperList[Index++] = 0x10A;
	CopperList[Index++] = INTERLEAVEDMOD;

	// Copper sky
	UWORD *Copperlist = &CopperList[Index];

	for (UWORD y = 0; y < SCROLLER_START_LINE; ++y)
	{
		AddSkyLine(&Copperlist, y);
	}

	Index = (UWORD)(Copperlist - CopperList);

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

	// BPLCON1: horizontal pixel shift for BPL2 (even plane = shadow), active for the whole scroller region.
	// BPL2 pointer is set SHADOW_DY/2 bitmap rows ahead so the shadow appears SHADOW_DY display lines below.
	CopperList[Index++] = 0x102;
	CopperList[Index++] = (UWORD)(SHADOW_DX << 4);

	// Copper sky behind scroller
	// Shadow Copper control lines (relative to SCROLLER_START_LINE):
	//   y = SCROLLER_START_LINE + SHADOW_DY - 1: set BPL2MOD to go back SHADOW_DY rows
	//   y = SCROLLER_START_LINE + SHADOW_DY    : restore BPL2MOD, apply BPLCON1 horizontal shift
	Copperlist = &CopperList[Index];

	for (UWORD y = SCROLLER_START_LINE; y < SCREENHEIGHT; ++y)
	{
		AddSkyLine(&Copperlist, y);

		// Per-line rainbow: MOVE COLOR01 + MOVE COLOR03; store direct pointer to the COLOR01 value slot
		*Copperlist++ = 0x182;
		ScrollRainbowColorPtr[y - SCROLLER_START_LINE] = Copperlist;
		*Copperlist++ = SCROLLER_TEXT_COLOR;
		*Copperlist++ = 0x186;
		*Copperlist++ = SCROLLER_TEXT_COLOR;

		const UWORD yr = y - SCROLLER_START_LINE;
		const BOOL inDoubleZone = (yr < SCROLLER_CHAR_DISPLAY);

		// Row 4x-stretch: hold the same bitmap row for 3 lines, advance on the 4th.
		// yr % 4 in {0,1,2}: MOD = -(BYTESPERROW)  — re-reads same bitmap row.
		// yr % 4 == 3:       MOD = INTERLEAVEDMOD  — advances to next bitmap row.
		// BPL2 starts SHADOW_DY/4 bitmap rows ahead (= SHADOW_DY display lines below BPL1).
		if (inDoubleZone)
		{
			const UWORD mod = ((yr & 3u) == 3u) ? INTERLEAVEDMOD : (UWORD)(-(BYTESPERROW));
			*Copperlist++ = 0x108;
			*Copperlist++ = mod;
			*Copperlist++ = 0x10A;
			*Copperlist++ = mod;
		}
	}

	Index = (UWORD)(Copperlist - CopperList);

	// Copper list end
	CopperList[Index++] = 0xFFFF;
	CopperList[Index++] = 0xFFFE;

	*COP1LC = (ULONG)CopperList;

	return TRUE;
}

void Update_BitplanePointers(UBYTE Buffer)
{
	const ULONG Base = (ULONG)ScreenBitmap[Buffer]->Planes[0];
	const ULONG ScrollAddr = Base + SCROLLER_BPLPOINTER;

	CopperList[ScrollBPL1PTH_Idx] = (UWORD)(ScrollAddr >> 16);
	CopperList[ScrollBPL1PTL_Idx] = (UWORD)ScrollAddr;

	// BPL2 (shadow) starts SHADOW_DY/4 bitmap rows BEHIND BPL1 (lower address = earlier row).
	// With 4x stretch each bitmap row is held for 4 display lines, so BPL2 shows the same
	// bitmap row 4 display lines AFTER BPL1 → shadow appears SHADOW_DY lines below the text.
	const ULONG ShadowAddr = ScrollAddr - (ULONG)(SHADOW_DY / 4u) * INTERLEAVED_STRIDE;
	CopperList[ScrollBPL2PTH_Idx] = (UWORD)(ShadowAddr >> 16);
	CopperList[ScrollBPL2PTL_Idx] = (UWORD)ShadowAddr;
}

void Update_ScrollerRainbow(void)
{
	UpdateScrollerRainbow(ScrollRainbowColorPtr, RainbowTab, (UWORD)RainbowPhase, SCROLLER_LINES);
	++RainbowPhase;
}

// =====================================================================
// Cleanup & Main
// =====================================================================

void Cleanup_All(void)
{
	// Make sure no outstanding blit is still touching screen memory before freeing resources.
	lwmf_WaitBlitter();

	Cleanup_SineScroller();

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

	if (!lwmf_InitScreenBitmaps())
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

	lwmf_TakeOverOS();

	UBYTE CurrentBuffer = 1;
	Update_BitplanePointers(0);

	while (*CIAA_PRA & 0x40)
	{
		// Clear only the bitmap rows actually used by the scroller:
		// rows SCROLLER_CLEAR_START..SCROLLER_CLEAR_START+SCROLLER_CLEAR_LINES-1 (99..145).
		lwmf_BlitClearLines(SCROLLER_CLEAR_START, SCROLLER_CLEAR_LINES, (long*)ScreenBitmap[CurrentBuffer]->Planes[0]);

		Update_ScrollerRainbow();
		Draw_SineScroller(CurrentBuffer);

		DBG_COLOR(0x0F0);          /* green = free time until VBlank */
		lwmf_WaitVertBlank();
		DBG_COLOR(0x000);          /* end of green bar */
		Update_BitplanePointers(CurrentBuffer);
		CurrentBuffer ^= 1;

	}

	Cleanup_All();
	return 0;
}
