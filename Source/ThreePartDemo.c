//**********************************************************************
//* Three-Part Demo for Amiga with at least OS 3.0                     *
//*                                                                    *
//* (C) 2020-2026 by Stefan Kubsch                                     *
//* Project for vbcc                                                   *
//*                                                                    *
//* Compile & link with:                                               *
//* make_ThreePartDemo.cmd                                             *
//*                                                                    *
//* Quit with mouse click                                              *
//**********************************************************************

#include "lwmf/lwmf.h"

// Enable (set to 1) for debugging
// When enabled, load per frame will be displayed via Color changing of background
#define DEBUG 				0

// =====================================================================
// Screen settings
// =====================================================================

// Layout: 84 + 1 + 85 + 1 + 85 = 256
#define LOGO_LINES          84
#define WHITE_LINE_1        84
#define PLASMA_START_LINE   85
#define PLASMA_LINES        85
#define WHITE_LINE_2        170
#define SCROLLER_START_LINE 171
#define SCROLLER_LINES      85

// =====================================================================
// Double buffering
// =====================================================================

struct BitMap* ScreenBitmap[2] = { NULL, NULL };

// =====================================================================
// MODPlayer (ptplayer)
// =====================================================================

struct MODFile MOD_Demosong;

// =====================================================================
// Bouncing Text Logo
// =====================================================================

struct lwmf_Image* LogoBitmap = NULL;

// Saved Color palette
UWORD LogoPalette[8] = {0x003, 0x368, 0x134, 0x012, 0x246,	0x146, 0x123, 0x001};

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

	lwmf_BlitTile((long*)LogoBitmap->Image->Planes[0], 0, 0, (long*)ScreenBitmap[Buffer]->Planes[0], LogoSinTabX[SinTabCount], LogoSinTabY[SinTabCount], LOGO_WIDTH, LOGO_HEIGHT, 320);

	if (++SinTabCount >= 63)
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

struct Scrollfont
{
	struct lwmf_Image* FontBitmap;
	char* Text;
	char* CharMap;
	UWORD TextLength;
	UWORD CharMapLength;
	UWORD Length;
	WORD ScrollX;
	WORD Feed;
	UBYTE CharWidth;
	UBYTE CharHeight;
	UBYTE CharSpacing;
	UBYTE CharOverallWidth;
	WORD *ColumnSrc;
	WORD *ColumnDst;
	UWORD ColumnCount;
	UWORD FirstVisibleColumn;
	WORD LastScrollX;
} Font;

// Sine table for scroller Y positions (center=203, amplitude=30)
// Scroller region = lines 171-255, char height 20 → Y range 171-235
static const UBYTE ScrollSinTab[SCREENWIDTH] =
{
	203,204,205,206,207,207,208,209,210,211,212,213,214,214,215,216,217,218,218,219,220,221,221,222,223,223,224,225,225,226,226,227,228,228,229,229,229,230,230,231,
	231,231,232,232,232,232,232,233,233,233,233,233,233,233,233,233,233,233,233,232,232,232,232,231,231,231,231,230,230,229,229,228,228,227,227,226,226,225,225,224,
	223,223,222,221,220,220,219,218,217,217,216,215,214,213,212,212,211,210,209,208,207,206,205,205,204,203,202,201,200,199,198,197,196,196,195,194,193,192,191,191,
	190,189,188,187,187,186,185,184,184,183,182,182,181,180,180,179,179,178,178,177,177,176,176,176,175,175,175,174,174,174,174,173,173,173,173,173,173,173,173,173,
	173,173,173,173,174,174,174,174,175,175,175,176,176,176,177,177,178,178,179,179,180,180,181,182,182,183,184,184,185,186,186,187,188,189,190,190,191,192,193,194,
	195,195,196,197,198,199,200,201,202,203,204,204,205,206,207,208,209,210,211,211,212,213,214,215,216,217,217,218,219,220,220,221,222,222,223,224,224,225,226,226,
	227,227,228,228,229,229,230,230,230,231,231,231,232,232,232,232,233,233,233,233,233,233,233,233,233,233,233,233,232,232,232,232,232,231,231,231,230,230,230,229,
	229,228,228,227,227,226,225,225,224,224,223,222,222,221,220,219,219,218,217,216,215,215,214,213,212,211,210,209,209,208,207,206,205,204,203,202,201,200,200,199
};

UWORD ScrollerPalette[8] = {0x003, 0xC0D, 0x333, 0x888, 0xFFF, 0x000, 0x000, 0x000};
static WORD SameYRunEnd[SCREENWIDTH];

static void BuildExactSineRunEnds(const UBYTE *SinTab, WORD ScreenLimit, WORD Feed)
{
	if (Feed <= 0 || ScreenLimit <= 0)
	{
		return;
	}

	WORD phaseCount = Feed;

	if (phaseCount > ScreenLimit)
	{
		phaseCount = ScreenLimit;
	}

	for (WORD phase = 0; phase < phaseCount; ++phase)
	{
		WORD x = phase;

		while ((x + Feed) < ScreenLimit)
		{
			x += Feed;
		}

		WORD runEnd = x;
		UBYTE y = SinTab[x];
		SameYRunEnd[x] = x;

		x -= Feed;

		while (x >= 0)
		{
			if (SinTab[x] == y)
			{
				SameYRunEnd[x] = runEnd;
			}
			else
			{
				runEnd = x;
				y = SinTab[x];
				SameYRunEnd[x] = x;
			}

			x -= Feed;
		}
	}
}

BOOL Init_SineScroller(void)
{
	if (!(Font.FontBitmap = lwmf_LoadImage("gfx/ScrollFont1.iff")))
	{
		return FALSE;
	}

	Font.Text = "...WELL, WELL...NOT PERFECT, BUT STILL WORKING ON IT !!! HAVE FUN WATCHING THE DEMO AND ENJOY YOUR AMIGA !!! MUSIC - BEAMS OF LIGHT BY WALKMAN 1989...CODE AND GFX - DEEP4 2026...";
	Font.CharMap = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!-,+?*()";
	Font.CharWidth = 15;
	Font.CharHeight = 20;
	Font.CharSpacing = 1;
	Font.Feed = 2;
	Font.CharOverallWidth = Font.CharWidth + Font.CharSpacing;
	Font.ScrollX = SCREENWIDTH;
	Font.TextLength = 0;
	Font.CharMapLength = 0;
	Font.Length = 0;
	Font.ColumnSrc = NULL;
	Font.ColumnDst = NULL;
	Font.ColumnCount = 0;
	Font.FirstVisibleColumn = 0;
	Font.LastScrollX = Font.ScrollX;

	while (Font.Text[Font.TextLength] != 0x00)
	{
		++Font.TextLength;
	}

	WORD CharLookup[128];
	UWORD MapPos = 0;
	const WORD Feed = Font.Feed;
	const WORD CharWidth = Font.CharWidth;
	const WORD CharOverallWidth = Font.CharOverallWidth;

	for (UWORD k = 0; k < 128; ++k)
	{
		CharLookup[k] = -1;
	}

	while (Font.CharMap[Font.CharMapLength] != 0x00)
	{
		CharLookup[(UBYTE)Font.CharMap[Font.CharMapLength]] = MapPos;
		MapPos += CharOverallWidth;
		++Font.CharMapLength;
	}

	Font.Length = Font.TextLength * CharOverallWidth;

	// Count
	for (UWORD i = 0; i < Font.TextLength; ++i)
	{
		const UBYTE c = (UBYTE)Font.Text[i];
		const WORD MapVal = (c < 128) ? CharLookup[c] : -1;

		if (MapVal >= 0)
		{
			WORD x1 = 0;

			while (x1 < CharWidth)
			{
				++Font.ColumnCount;
				x1 += Feed;
			}
		}
	}

	if (Font.ColumnCount == 0)
	{
		return TRUE;
	}

	if (!(Font.ColumnSrc = AllocVec(sizeof(WORD) * Font.ColumnCount, NULL)))
	{
		return FALSE;
	}

	if (!(Font.ColumnDst = AllocVec(sizeof(WORD) * Font.ColumnCount, NULL)))
	{
		FreeVec(Font.ColumnSrc);
		Font.ColumnSrc = NULL;
		return FALSE;
	}

	// Fill
	UWORD ColumnIndex = 0;

	for (UWORD i = 0; i < Font.TextLength; ++i)
	{
		const UBYTE c = (UBYTE)Font.Text[i];
		const WORD MapVal = (c < 128) ? CharLookup[c] : -1;

		if (MapVal >= 0)
		{
			const WORD CharBaseX = i * CharOverallWidth;
			WORD x1 = 0;
			WORD srcx = MapVal;

			while (x1 < CharWidth)
			{
				Font.ColumnDst[ColumnIndex] = CharBaseX + x1;
				Font.ColumnSrc[ColumnIndex] = srcx;
				++ColumnIndex;

				x1 += Feed;
				srcx += Feed;
			}
		}
	}

	BuildExactSineRunEnds(ScrollSinTab, SCREENWIDTH - Font.Feed, Font.Feed);

	return TRUE;
}

static UWORD UpdateFirstVisibleColumn(WORD ScrollX)
{
    if (Font.ColumnCount == 0)
	{
        return 0;
	}

    UWORD i;

    if (ScrollX > Font.LastScrollX || (Font.LastScrollX - ScrollX) > (Font.Feed << 2))
	{
        const WORD Target = -ScrollX;
        UWORD Left = 0;
		UWORD Right = Font.ColumnCount;

        while (Left < Right)
		{
            const UWORD Mid = (Left + Right) >> 1;

            if (Font.ColumnDst[Mid] < Target)
			{
                Left = Mid + 1;
			}
			else
            {
				Right = Mid;
			}
        }

        if (Left > 0)
		{
			--Left;
		}

        i = Left;
    }
	else
	{
        i = Font.FirstVisibleColumn;

        while (i < Font.ColumnCount)
		{
            if ((ScrollX + Font.ColumnDst[i] + Font.Feed) >= 0)
			{
                break;
			}

			++i;
        }
    }

    Font.FirstVisibleColumn = i;
    Font.LastScrollX = ScrollX;

    return i;
}

void Draw_SineScroller(UBYTE Buffer)
{
	const WORD ScrollX = Font.ScrollX;
	const WORD Feed = Font.Feed;
	const WORD Step = Feed << 1;
	const WORD CharHeight = Font.CharHeight;
	const WORD ScreenLimit = SCREENWIDTH - Feed;
	const WORD LeftVisibleTextX = -ScrollX;
	const WORD RightVisibleTextX = ScreenLimit - ScrollX;
	const UBYTE *SinTab = ScrollSinTab;

	WORD *ColumnDst = Font.ColumnDst;
	WORD *ColumnSrc = Font.ColumnSrc;
	WORD *DstEnd = ColumnDst + Font.ColumnCount;

	struct BitMap *SrcBitmap = Font.FontBitmap->Image;
	struct BitMap *DstBitmap = ScreenBitmap[Buffer];

	if (ColumnDst < DstEnd)
	{
		UWORD i = UpdateFirstVisibleColumn(ScrollX);
		WORD *dstPtr = ColumnDst + i;
		WORD *srcPtr = ColumnSrc + i;

		while (dstPtr < DstEnd && *dstPtr < LeftVisibleTextX)
		{
			++dstPtr;
			++srcPtr;
		}

		while (dstPtr < DstEnd)
		{
			const WORD dstTextX = *dstPtr;

			if (dstTextX >= RightVisibleTextX)
			{
				break;
			}

			const WORD srcX = *srcPtr;
			const WORD dstX = ScrollX + dstTextX;
			const UBYTE y = SinTab[dstX];
			const WORD runEndX = SameYRunEnd[dstX];
			WORD width = Feed;

			WORD expectedDstTextX = dstTextX + Feed;
			WORD expectedSrcX = srcX + Feed;

			WORD *scanDstPtr = dstPtr;
			WORD *scanSrcPtr = srcPtr;

			for (;;)
			{
				++scanDstPtr;
				++scanSrcPtr;

				if (scanDstPtr >= DstEnd)
				{
					break;
				}

				const WORD nextDstTextX = *scanDstPtr;

				if (nextDstTextX != expectedDstTextX)
				{
					break;
				}

				if (nextDstTextX >= RightVisibleTextX)
				{
					break;
				}

				const WORD nextSrcX = *scanSrcPtr;

				if (nextSrcX != expectedSrcX)
				{
					break;
				}

				const WORD nextDstX = ScrollX + nextDstTextX;

				if (nextDstX > runEndX)
				{
					break;
				}

				width += Feed;
				expectedDstTextX += Feed;
				expectedSrcX += Feed;
			}

			BltBitMap(SrcBitmap, srcX, 0, DstBitmap, dstX, y, width, CharHeight, 0xC0, 0x01, NULL);

			dstPtr = scanDstPtr;
			srcPtr = scanSrcPtr;
		}
	}

	Font.ScrollX -= Step;

	if (Font.ScrollX < -Font.Length)
	{
		Font.ScrollX = SCREENWIDTH;
		Font.FirstVisibleColumn = 0;
		Font.LastScrollX = Font.ScrollX;
	}
}

void Cleanup_SineScroller(void)
{
	if (Font.FontBitmap)
	{
		lwmf_DeleteImage(Font.FontBitmap);
	}

	if (Font.ColumnDst)
	{
		FreeVec(Font.ColumnDst);
		Font.ColumnDst = NULL;
	}

	if (Font.ColumnSrc)
	{
		FreeVec(Font.ColumnSrc);
		Font.ColumnSrc = NULL;
	}
}

// =====================================================================
// Copper
// =====================================================================

UWORD* CopperList = NULL;
UWORD PlasmaStart = 0;

UWORD BPL1PTH_Idx = 0;
UWORD BPL1PTL_Idx = 0;
UWORD BPL2PTH_Idx = 0;
UWORD BPL2PTL_Idx = 0;
UWORD BPL3PTH_Idx = 0;
UWORD BPL3PTL_Idx = 0;

UWORD ScrollBPL1PTH_Idx = 0;
UWORD ScrollBPL1PTL_Idx = 0;
UWORD ScrollBPL2PTH_Idx = 0;
UWORD ScrollBPL2PTL_Idx = 0;
UWORD ScrollBPL3PTH_Idx = 0;
UWORD ScrollBPL3PTL_Idx = 0;

#define PLASMA_COLS 40
#define LINE_WORDS (2 + 2 + 2 * PLASMA_COLS + 2)

// VPOS offset for PAL display (first visible Line = $2C = 44)
#define VPOS_OFFSET     		0x2C

// VPOS helpers
#define LOGO_VPOS_START     	VPOS_OFFSET
#define WHITE1_VPOS         	VPOS_OFFSET + WHITE_LINE_1
#define PLASMA_VPOS_START   	VPOS_OFFSET + PLASMA_START_LINE
#define WHITE2_VPOS         	VPOS_OFFSET + WHITE_LINE_2
#define SCROLLER_VPOS_START 	VPOS_OFFSET + SCROLLER_START_LINE
#define SCROLLER_BPLPOINTER		SCROLLER_START_LINE * BYTESPERROW * NUMBEROFBITPLANES

// =====================================================================
// Morning sky copper background
// =====================================================================

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

static UWORD SkyColorForLine(UWORD y, UWORD totalLines)
{
	if (y == 0)
	{
		return SkyKeys[0].Color;
	}

	UWORD p = (UWORD)(((ULONG)y * SCREENHEIGHT) / (ULONG)(totalLines - 1));

	for (UWORD i = 0; i < (sizeof(SkyKeys) / sizeof(SkyKeys[0])) - 1; ++i)
	{
		UWORD p0 = SkyKeys[i].Line;
		UWORD p1 = SkyKeys[i + 1].Line;

		if (p >= p0 && p <= p1)
		{
			const UWORD Span = p1 - p0;
			const UWORD t = p - p0;

			if (!Span)
			{
				return SkyKeys[i].Color;
			}

			return RGB4_Lerp(SkyKeys[i].Color, SkyKeys[i + 1].Color, t, Span);
		}
	}

	return SkyKeys[(sizeof(SkyKeys) / sizeof(SkyKeys[0])) - 1].Color;
}

static void AddSkyLine(UWORD **cl, UWORD y)
{
	const UWORD VPOS = VPOS_OFFSET + y;

	// VPOS wrap at 256
	if (VPOS == 256)
	{
		*(*cl)++ = 0xFFDF;
		*(*cl)++ = 0xFFFE;
	}

	*(*cl)++ = ((VPOS & 0xFF) << 8) | 0x07;
	*(*cl)++ = 0xFFFE;
	*(*cl)++ = 0x180;
	*(*cl)++ = SkyColorForLine(y, SCREENHEIGHT);
}

BOOL Init_CopperList(void)
{
	const ULONG CopperListLength = 80 + (PLASMA_LINES * LINE_WORDS) + (SCREENHEIGHT * 4) + 64;

	if (!(CopperList = (UWORD*)AllocVec(CopperListLength * sizeof(UWORD), MEMF_CHIP | MEMF_CLEAR)))
	{
		return FALSE;
	}

	const UWORD INTERLEAVEDMOD = (BYTESPERROW * (NUMBEROFBITPLANES - 1));
	UWORD Index = 0;

	// Slow fetch mode (AGA compatibility)
	CopperList[Index++] = 0x1FC;
	CopperList[Index++] = 0x0000;

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

	// BPLCON3
	CopperList[Index++] = 0x106;
	CopperList[Index++] = 0x0C00;

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
	UWORD *cl = &CopperList[Index];

	for (UWORD y = 0; y < WHITE_LINE_1; ++y)
	{
		AddSkyLine(&cl, y);
	}

	Index = (UWORD)(cl - CopperList);

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
	CopperList[Index++] = SkyColorForLine(WHITE_LINE_2 + 1, SCREENHEIGHT);

	// BPLCON0 Switch to 3 bitplanes for scroller
	CopperList[Index++] = (SCROLLER_VPOS_START << 8) | 0x07;
	CopperList[Index++] = 0xFFFE;
	CopperList[Index++] = 0x100;
	CopperList[Index++] = 0x3200;

	// BPL1PTH/PTL
	CopperList[Index++] = 0x0E0;
	ScrollBPL1PTH_Idx = Index;
	CopperList[Index++] = 0x0000;

	CopperList[Index++] = 0x0E2;
	ScrollBPL1PTL_Idx = Index;
	CopperList[Index++] = 0x0000;

	// BPL2PTH/PTL
	CopperList[Index++] = 0x0E4;
	ScrollBPL2PTH_Idx = Index;
	CopperList[Index++] = 0x0000;

	CopperList[Index++] = 0x0E6;
	ScrollBPL2PTL_Idx = Index;
	CopperList[Index++] = 0x0000;

	// BPL3PTH/PTL
	CopperList[Index++] = 0x0E8;
	ScrollBPL3PTH_Idx = Index;
	CopperList[Index++] = 0x0000;

	CopperList[Index++] = 0x0EA;
	ScrollBPL3PTL_Idx = Index;
	CopperList[Index++] = 0x0000;

	// COLOR01-COLOR07 only
	// COLOR00 stays reserved for the copper sky behind the scroller
	for (UBYTE c = 1; c < 8; ++c)
	{
		CopperList[Index++] = 0x180 + c * 2;
		CopperList[Index++] = ScrollerPalette[c];
	}

	// Copper sky behind scroller and below it
	cl = &CopperList[Index];

	for (UWORD y = WHITE_LINE_2 + 1; y < SCREENHEIGHT; ++y)
	{
		AddSkyLine(&cl, y);
	}

	Index = (UWORD)(cl - CopperList);

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
	ULONG addr;

	// Logo region: 3 bitplane pointers
	addr = (ULONG)ScreenBitmap[Buffer]->Planes[0];
	CopperList[BPL1PTH_Idx] = (UWORD)(addr >> 16);
	CopperList[BPL1PTL_Idx] = (UWORD)(addr & 0xFFFF);

	addr = (ULONG)ScreenBitmap[Buffer]->Planes[1];
	CopperList[BPL2PTH_Idx] = (UWORD)(addr >> 16);
	CopperList[BPL2PTL_Idx] = (UWORD)(addr & 0xFFFF);

	addr = (ULONG)ScreenBitmap[Buffer]->Planes[2];
	CopperList[BPL3PTH_Idx] = (UWORD)(addr >> 16);
	CopperList[BPL3PTL_Idx] = (UWORD)(addr & 0xFFFF);

	// Scroller region: 3 bitplane pointers
	addr = (ULONG)ScreenBitmap[Buffer]->Planes[0] + SCROLLER_BPLPOINTER;
	CopperList[ScrollBPL1PTH_Idx] = (UWORD)(addr >> 16);
	CopperList[ScrollBPL1PTL_Idx] = (UWORD)(addr & 0xFFFF);

	addr = (ULONG)ScreenBitmap[Buffer]->Planes[1] + SCROLLER_BPLPOINTER;
	CopperList[ScrollBPL2PTH_Idx] = (UWORD)(addr >> 16);
	CopperList[ScrollBPL2PTL_Idx] = (UWORD)(addr & 0xFFFF);

	addr = (ULONG)ScreenBitmap[Buffer]->Planes[2] + SCROLLER_BPLPOINTER;
	CopperList[ScrollBPL3PTH_Idx] = (UWORD)(addr >> 16);
	CopperList[ScrollBPL3PTL_Idx] = (UWORD)(addr & 0xFFFF);
}

// =====================================================================
// Copper & Plasma
// =====================================================================

// Wave sine table (256 entries, values 0..63)
static const UBYTE PlasmaSin[256] =
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

// 2D RGB plasma: base table (64-entry period, doubled to 128)
static const UBYTE CompBase[128] =
{
	8, 8, 9,10,10,11,12,12,13,13,14,14,14,15,15,15,15,15,15,15,14,14,14,13,13,12,12,11,10,10, 9, 8,
	 8, 7, 6, 5, 5, 4, 3, 3, 2, 2, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 2, 2, 3, 3, 4, 5, 5, 6, 7,
	 8, 8, 9,10,10,11,12,12,13,13,14,14,14,15,15,15,15,15,15,15,14,14,14,13,13,12,12,11,10,10, 9, 8,
	 8, 7, 6, 5, 5, 4, 3, 3, 2, 2, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 2, 2, 3, 3, 4, 5, 5, 6, 7
};

#define EMIT_PLASMA_COLOR() \
	do { \
		*lcop++ = 0x01800000UL \
		        | ((ULONG)(*rp++) << 8) \
		        | ((ULONG)(*gp++) << 4) \
		        |  (ULONG)(*bp++); \
	} while (0)

void Update_Plasma(void)
{
	static UBYTE PlasmaFrameRed = 0;
	static UBYTE PlasmaFrameGreen = 90;

	UBYTE idx2 = PlasmaFrameRed;
	UBYTE idx5 = PlasmaFrameGreen;

	UWORD *lineBase = &CopperList[PlasmaStart];

	for (UWORD row = 0; row < PLASMA_LINES; ++row)
	{
		const UBYTE r_off = PlasmaSin[idx2] & 127;
		const UBYTE g_off = PlasmaSin[idx5] & 127;

		// blue offset as average of red and green for better color distribution
		const UBYTE b_off = (UBYTE)(((UWORD)r_off + (UWORD)g_off) >> 1);

		const UBYTE *rp = &CompBase[r_off];
		const UBYTE *gp = &CompBase[g_off];
		const UBYTE *bp = &CompBase[b_off];

		lineBase[1] = (UWORD)(((UWORD)rp[0] << 8) | ((UWORD)gp[0] << 4) | (UWORD)bp[0]);

		// lineBase + 4 must point to longword-aligned copper MOVE data.
		// If CopperList is not longword-aligned, switch this back to UWORD writes.
		ULONG *lcop = (ULONG *)(void *)(lineBase + 4);

		// first color already written to lineBase[1], so skip entry 0
		++rp;
		++gp;
		++bp;

		for (UWORD block = 0; block < 5; ++block)
		{
			EMIT_PLASMA_COLOR();
			EMIT_PLASMA_COLOR();
			EMIT_PLASMA_COLOR();
			EMIT_PLASMA_COLOR();
			EMIT_PLASMA_COLOR();
			EMIT_PLASMA_COLOR();
			EMIT_PLASMA_COLOR();
			EMIT_PLASMA_COLOR();
		}

		idx2 += 2;
		idx5 += 5;
		lineBase += LINE_WORDS;
	}

	PlasmaFrameRed += 3;
	PlasmaFrameGreen += 2;
}

#undef EMIT_PLASMA_COLOR

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
		FreeVec(CopperList);
	}

	for (UBYTE i = 0; i < 2; ++i)
	{
		if (ScreenBitmap[i])
		{
			FreeBitMap(ScreenBitmap[i]);
		}
	}

	lwmf_CleanupAll();
}

int main()
{
	if (lwmf_LoadGraphicsLib() != 0)
	{
		return 20;
	}

	if (lwmf_LoadDatatypesLib() != 0)
	{
		Cleanup_All();
		return 20;
	}

	if (!lwmf_InitModPlayer(&MOD_Demosong, "sfx/beamsoflight.mod"))
	{
		Cleanup_All();
		return 20;
	}

	for (UBYTE i = 0; i < 2; ++i)
	{
		if (!(ScreenBitmap[i] = AllocBitMap(SCREENWIDTH, SCREENHEIGHT, NUMBEROFBITPLANES, BMF_INTERLEAVED | BMF_CLEAR, NULL)))
		{
			Cleanup_All();
			return 20;
		}
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

	lwmf_TakeOverOS();

	lwmf_StartMODPlayer(&MOD_Demosong);

	UBYTE CurrentBuffer = 1;
	Update_BitplanePointers(0);

	while (*CIAA_PRA & 0x40)
	{
		lwmf_OwnBlitter();
		// CLear screen with blitter while CPU updates plasma colors in copper list
		lwmf_ClearScreen((long*)ScreenBitmap[CurrentBuffer]->Planes[0]);
		// CPU updates plasma while blitter clears
		Update_Plasma();
		lwmf_DisownBlitter();

		// Draw effects into backbuffer
		Draw_TextLogo(CurrentBuffer);
		Draw_SineScroller(CurrentBuffer);

		if (DEBUG == 1)
		{
			*COLOR00 = 0xF00;
		}

		// Flip
		Update_BitplanePointers(CurrentBuffer);
		lwmf_WaitVertBlank();
		CurrentBuffer ^= 1;
	}

	lwmf_StopMODPlayer(&MOD_Demosong);

	Cleanup_All();
	return 0;
}
