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
	WORD* Map;
	UWORD TextLength;
	UWORD CharMapLength;
	UWORD Length;
	WORD ScrollX;
	WORD Feed;
	UBYTE CharWidth;
	UBYTE CharHeight;
	UBYTE CharSpacing;
	UBYTE CharOverallWidth;
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

BOOL Init_SineScroller(void)
{
	// ScrollFont.bsh is an ILBM (IFF) file
	// In this case it´s a "brush", made with Personal Paint on Amiga - a brush is smaller in size
	// The original IFF ScrollFont.iff is included in gfx
	if (!(Font.FontBitmap = lwmf_LoadImage("gfx/ScrollFont.bsh")))
	{
		return FALSE;
	}

	// Text & Font settings
	Font.Text = "...WELL, WELL...NOT PERFECT, BUT STILL WORKING ON IT !!! HAVE FUN WATCHING THE DEMO AND ENJOY YOUR AMIGA !!! (C) DEEP4 2021...";
	Font.CharMap = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!-,+?*()";
	Font.CharWidth = 15;
	Font.CharHeight = 20;
	Font.CharSpacing = 1;
	Font.Feed = 2;
	Font.CharOverallWidth = Font.CharWidth + Font.CharSpacing;
	Font.ScrollX = SCREENWIDTH;

	const char* const Text = Font.Text;
	const char* const CharMap = Font.CharMap;
	const UBYTE CharOverallWidth = Font.CharOverallWidth;

	// Count text length
	UWORD TextLength = 0;

	while (Text[TextLength] != 0x00)
	{
  		++TextLength;
	}

	Font.TextLength = TextLength;

	// Count charmap length and build reverse lookup table
	// Maps ASCII value -> pixel position in font bitmap (-1 = not found)
	WORD CharLookup[128];

	for (UWORD k = 0; k < 128; ++k)
	{
		CharLookup[k] = -1;
	}

	UWORD CharMapLength = 0;
	UWORD MapPos = 0;

	while (CharMap[CharMapLength] != 0x00)
	{
		CharLookup[(UBYTE)CharMap[CharMapLength]] = MapPos;
		MapPos += CharOverallWidth;
		++CharMapLength;
	}

	Font.CharMapLength = CharMapLength;
	Font.Length = TextLength * CharOverallWidth;

	if (!(Font.Map = AllocVec(sizeof(WORD) * TextLength, MEMF_ANY)))
	{
		return FALSE;
	}

	// Pre-calc char positions via lookup table - O(n) instead of O(n*m)
	WORD* const Map = Font.Map;

	for (UWORD i = 0; i < TextLength; ++i)
	{
		const UBYTE c = (UBYTE)Text[i];
		Map[i] = (c < 128) ? CharLookup[c] : -1;
	}

	return TRUE;
}

void Draw_SineScroller(void)
{
	const WORD* const Map = Font.Map;
	const UWORD TextLength = Font.TextLength;
	const UBYTE CharOverallWidth = Font.CharOverallWidth;
	const UBYTE CharWidth = Font.CharWidth;
	const WORD Feed = Font.Feed;
	const UBYTE CharHeight = Font.CharHeight;
	const UWORD ScreenLimit = SCREENWIDTH - Feed;
	struct BitMap* const SrcBM = Font.FontBitmap->Image;
	struct BitMap* const DstBM = RenderPort.BitMap;

	WORD XPos = Font.ScrollX;

	for (UWORD i = 0; i < TextLength; ++i)
	{
		const WORD MapVal = Map[i];

		if (MapVal == -1)
		{
			XPos += CharOverallWidth;
			continue;
		}

		// Skip characters entirely off-screen to the left
		if (XPos + CharOverallWidth < 0)
		{
			XPos += CharOverallWidth;
			continue;
		}

		// All remaining characters are off-screen to the right
		if (XPos >= SCREENWIDTH)
		{
			break;
		}

		const WORD MapEnd = MapVal + CharWidth;

		for (UWORD x1 = 0, x = MapVal; x < MapEnd; x1 += Feed, x += Feed)
		{
			const WORD TempPosX = XPos + x1;

			if (TempPosX >= 0 && TempPosX < ScreenLimit)
			{
				BltBitMap(SrcBM, x, 0, DstBM, TempPosX, ScrollSinTab[TempPosX], Feed, CharHeight, 0xC0, 0x01, NULL);
			}
			else if (TempPosX >= ScreenLimit)
			{
				break;
			}
		}

		XPos += CharOverallWidth;
	}

	Font.ScrollX -= Feed << 1;

	if (Font.ScrollX < -Font.Length)
	{
		Font.ScrollX = SCREENWIDTH;
	}
}

void Cleanup_SineScroller(void)
{
	if (Font.FontBitmap)
	{
		lwmf_DeleteImage(Font.FontBitmap);
	}

	if (Font.Map)
	{
		FreeVec(Font.Map);
	}
}


#endif /* SineScroller_H */