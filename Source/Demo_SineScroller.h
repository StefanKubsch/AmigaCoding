#ifndef SineScroller_H
#define SineScroller_H


//***************************************
//* Simple sine scroller           		*
//*								   		*
//* (C) 2020-2026 by Stefan Kubsch      *
//***************************************

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

// Generate sinus table
// for (UWORD i = 0; i < SCREENWIDTH; ++i)
// {
// 		ScrollSinTab[i] = 115 + (UBYTE)(sin(0.03f * (float)i) * 30.0f);
// }

UBYTE ScrollSinTab[SCREENWIDTH] =
{
	115,115,116,117,118,119,120,121,122,123,123,124,125,126,127,128,128,129,130,131,131,132,133,134,134,135,136,136,
	137,137,138,139,139,140,140,141,141,141,142,142,142,143,143,143,144,144,144,144,144,144,144,144,144,144,144,144,
	144,144,144,144,144,143,143,143,143,142,142,142,141,141,140,140,139,139,138,138,137,137,136,135,135,134,133,133,
	132,131,130,130,129,128,127,127,126,125,124,123,122,121,121,120,119,118,117,116,115,115,114,113,113,112,111,110,
	109,108,107,106,106,105,104,103,102,101,101,100,99,98,98,97,96,96,95,94,94,93,92,92,91,91,90,90,89,89,89,88,88,
	87,87,87,87,86,86,86,86,86,86,86,86,86,86,86,86,86,86,86,86,86,87,87,87,87,88,88,88,89,89,90,90,91,91,92,92,93,
	94,94,95,95,96,97,98,98,99,100,101,101,102,103,104,105,105,106,107,108,109,110,111,112,112,113,114,115,115,116,
	117,118,119,119,120,121,122,123,124,125,126,126,127,128,129,130,130,131,132,133,133,134,135,135,136,137,137,138,
	138,139,139,140,140,141,141,142,142,142,143,143,143,143,144,144,144,144,144,144,144,144,144,144,144,144,144,144,
	144,144,144,143,143,143,143,142,142,141,141,141,140,140,139,139,138,138,137,136,136,135,134,134,133,132,132,131,
	130,129,128,128,127,126,125,124,124,123,122,121,120,119,118,117,116,116,115,115,114,113,112,111
};

static UWORD FindFirstVisibleColumn_Binary(WORD ScrollX)
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

	return Left;
}

static UWORD UpdateFirstVisibleColumn(WORD ScrollX)
{
	UWORD i = Font.FirstVisibleColumn;

	if (Font.ColumnCount == 0)
	{
		return 0;
	}

	if (ScrollX > Font.LastScrollX || (Font.LastScrollX - ScrollX) > (Font.Feed << 2))
	{
		i = FindFirstVisibleColumn_Binary(ScrollX);
		Font.FirstVisibleColumn = i;
		Font.LastScrollX = ScrollX;
		return i;
	}

	while (i < Font.ColumnCount)
	{
		if ((ScrollX + Font.ColumnDst[i] + Font.Feed) >= 0)
		{
			break;
		}

		++i;
	}

	Font.FirstVisibleColumn = i;
	Font.LastScrollX = ScrollX;

	return i;
}

BOOL Init_SineScroller(void)
{
	if (!(Font.FontBitmap = lwmf_LoadImage("gfx/ScrollFont1.iff")))
	{
		return FALSE;
	}

	Font.Text = "...WELL, WELL...NOT PERFECT, BUT STILL WORKING ON IT !!! HAVE FUN WATCHING THE DEMO AND ENJOY YOUR AMIGA !!! (C) DEEP4 2026...";
	Font.CharMap = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!-,+?*()";
	Font.CharWidth = 15;
	Font.CharHeight = 20;
	Font.CharSpacing = 1;
	Font.Feed = 1;
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

	return TRUE;
}

void Draw_SineScroller(void)
{
	const WORD ScrollX = Font.ScrollX;
	const WORD Feed = Font.Feed;
	const WORD CharHeight = Font.CharHeight;
	const WORD ScreenLimit = SCREENWIDTH - Feed;
	const UBYTE *SinTab = ScrollSinTab;
	WORD *ColumnDst = Font.ColumnDst;
	WORD *ColumnSrc = Font.ColumnSrc;
	WORD *DstEnd = ColumnDst + Font.ColumnCount;

	struct BitMap *SrcBitmap = Font.FontBitmap->Image;
	struct BitMap *DstBitmap = RenderPort.BitMap;

	if (ColumnDst != DstEnd)
	{
		UWORD i = UpdateFirstVisibleColumn(ScrollX);
		WORD *dstPtr = ColumnDst + i;
		WORD *srcPtr = ColumnSrc + i;

		while (dstPtr < DstEnd)
		{
			WORD dstTextX = *dstPtr;
			WORD dstX = ScrollX + dstTextX;
			WORD srcX = *srcPtr;

			if (dstX >= ScreenLimit)
			{
				break;
			}

			if (dstX < 0)
			{
				++dstPtr;
				++srcPtr;
				continue;
			}

			{
				const WORD y = SinTab[dstX];
				WORD width = Feed;
				WORD lastDstTextX = dstTextX;
				WORD lastSrcX = srcX;
				WORD *nextDstPtr = dstPtr + 1;
				WORD *nextSrcPtr = srcPtr + 1;

				while (nextDstPtr < DstEnd)
				{
					const WORD nextDstTextX = *nextDstPtr;
					const WORD nextDstX = ScrollX + nextDstTextX;
					const WORD nextSrcX = *nextSrcPtr;
					WORD dy;

					if (nextDstX >= ScreenLimit)
					{
						break;
					}

					if (nextDstX < 0)
					{
						break;
					}

					if ((nextDstTextX - lastDstTextX) != Feed)
					{
						break;
					}

					if ((nextSrcX - lastSrcX) != Feed)
					{
						break;
					}

					dy = SinTab[nextDstX] - y;

					if (dy < 0)
					{
						dy = -dy;
					}

					if (dy > 1)
					{
						break;
					}

					width += Feed;
					lastDstTextX = nextDstTextX;
					lastSrcX = nextSrcX;

					++nextDstPtr;
					++nextSrcPtr;
				}

				BltBitMap(SrcBitmap, srcX, 0, DstBitmap, dstX, y, width, CharHeight, 0xC0, 0x01, NULL);

				dstPtr = nextDstPtr;
				srcPtr = nextSrcPtr;
			}
		}
	}

	Font.ScrollX -= Feed << 1;

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


#endif /* SineScroller_H */