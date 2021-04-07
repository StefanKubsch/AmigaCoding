#ifndef SineScroller_H
#define SineScroller_H


//***************************************
//* Simple sine scroller           		*
//*								   		*
//* (C) 2020-2021 by Stefan Kubsch      *
//***************************************

#include <math.h>
#include <string.h>

struct Scrollfont
{
	struct lwmf_Image* FontBitmap;
	char* Text;
	char* CharMap;
	WORD* Map;
	UBYTE CharWidth;
	UBYTE CharHeight;
	UBYTE CharSpacing;
	UBYTE CharOverallWidth;
	UWORD TextLength;
	UWORD CharMapLength;
	UWORD Length;
	WORD ScrollX;
} Font;

UBYTE ScrollSinTab[SCREENWIDTH];

BOOL Init_SineScroller(void)
{
	// ScrollFont.bsh is an ILBM (IFF) file
	// In this case it´s a "brush", made with Personal Paint on Amiga - a brush is smaller in size
	// The original IFF ScrollFont.iff is included in gfx
	if (!(Font.FontBitmap = lwmf_LoadImage("gfx/scrollfont.bsh")))
	{
		return FALSE;
	}

	// Text & Font settings
	Font.Text = "...WELL, WELL...NOT PERFECT, BUT STILL WORKING ON IT !!! HAVE FUN WATCHING THE DEMO AND ENJOY YOUR AMIGA !!!";
	Font.CharMap = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!-,+?*()";
	Font.CharWidth = 15;
	Font.CharHeight = 20;
	Font.CharSpacing = 1;
	Font.CharOverallWidth = Font.CharWidth + Font.CharSpacing;
	Font.ScrollX = SCREENWIDTH;
	Font.TextLength = strlen(Font.Text);
	Font.CharMapLength = strlen(Font.CharMap);
	Font.Length = Font.TextLength * Font.CharOverallWidth;

	if (!(Font.Map = AllocVec(sizeof(WORD) * Font.TextLength, MEMF_ANY | MEMF_CLEAR)))
	{
		return FALSE;
	}

	// Pre-calc char positions in map
	for (UWORD i = 0; i < Font.TextLength; ++i)
	{
		// use -1 if char not found, "space"
		Font.Map[i] = -1;

		for (UWORD j = 0, MapPos = 0; j < Font.CharMapLength; ++j)
		{
			if (*(Font.Text + i) == *(Font.CharMap + j))
			{
				Font.Map[i] = MapPos;
				break;
			}

			MapPos += Font.CharOverallWidth;
		}
	}

	// Generate sinus table
	for (UWORD i = 0; i < SCREENWIDTH; ++i)
	{
		ScrollSinTab[i] = 115 + (UBYTE)(sin(0.03f * (float)i) * 30.0f);
	}

	return TRUE;
}

void Draw_SineScroller(void)
{
	for (UWORD i = 0, XPos = Font.ScrollX; i < Font.TextLength; ++i)
	{
		if (Font.Map[i] == -1)
		{
			XPos += Font.CharOverallWidth;
			continue;
		}

		for (UWORD x1 = 0, x = Font.Map[i]; x < Font.Map[i] + Font.CharWidth; x1 += 2, x += 2)
		{
			const UWORD TempPosX = XPos + x1;

			if (TempPosX < SCREENWIDTH)
			{
				BltBitMap(Font.FontBitmap->Image, x, 0, RenderPort.BitMap, TempPosX, ScrollSinTab[TempPosX], 2, Font.CharHeight, 0xC0, 0x01, NULL);
			}
			else
			{
				break;
			}
		}

		XPos += Font.CharOverallWidth;
	}

	Font.ScrollX -= 4;

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