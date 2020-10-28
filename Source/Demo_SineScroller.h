#ifndef SineScroller_H
#define SineScroller_H


//**********************************
//* Simple sine scroller           *
//*								   *
//* (C) 2020 by Stefan Kubsch      *
//**********************************

#include <math.h>
#include <string.h>

BOOL Init_SineScroller(void);
void Cleanup_SineScroller(void);
void Draw_SineScroller(void);

struct Scrollfont
{
	struct lwmf_Image* FontBitmap;
	char* Text;
	char* CharMap;
	WORD* Map;
	UBYTE CharWidth;
	UBYTE CharHeight;
	UBYTE CharSpacing;
	UWORD TextLength;
	UWORD CharMapLength;
	UWORD Length;
	WORD ScrollX;
} Font;

UWORD ScrollSinTab[WIDTH];

BOOL Init_SineScroller(void)
{
	// Generate sinus table
	for (int i = 0; i < WIDTH; ++i)
	{
		ScrollSinTab[i] = 115 + (UWORD)(sin(0.03f * i) * 50.0f);
	}

	// Text & Font settings
	Font.Text = "...WELL, WELL...NOT PERFECT, BUT STILL WORKING ON IT !!!";
	Font.CharMap = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!-,+?*()";
	Font.CharWidth = 15;
	Font.CharHeight = 20;
	Font.CharSpacing = 1;
	Font.ScrollX = WIDTH;
	Font.TextLength = strlen(Font.Text);
	Font.CharMapLength = strlen(Font.CharMap);
	Font.Length = Font.TextLength * (Font.CharWidth + Font.CharSpacing);

	if (!(Font.FontBitmap = lwmf_LoadImage("gfx/scrollfont.iff")))
	{
		return FALSE;
	}

	if (!(Font.Map = AllocVec(sizeof(WORD) * Font.TextLength, MEMF_ANY | MEMF_CLEAR)))
	{
		return FALSE;
	}

	for (int i = 0; i < Font.TextLength; ++i)
	{
		Font.Map[i] = 0;

		for (int j = 0, MapPos = 0; j < Font.CharMapLength; ++j)
		{
			if (*(Font.Text + i) == *(Font.CharMap + j))
			{
				Font.Map[i] = MapPos;
				break;
			}

			MapPos += Font.CharWidth + Font.CharSpacing;
		}

		// char not found, space
		if (Font.Map[i] == 0)
		{
			Font.Map[i] = -1;
		}
	}

	return TRUE;
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

void Draw_SineScroller(void)
{
	for (int i = 0, XPos = Font.ScrollX; i < Font.TextLength; ++i)
	{
		for (int x1 = 0, x = Font.Map[i]; x < Font.Map[i] + Font.CharWidth; ++x1, ++x)
		{
			if (Font.Map[i] == -1)
			{
				break;
			}

			const UWORD TempPosX = XPos + x1;

			if (TempPosX < WIDTH)
			{
				BltBitMap(Font.FontBitmap->Image, x, 0, RenderPort.BitMap, TempPosX, ScrollSinTab[TempPosX], 1, Font.CharHeight, 0xC0, 0x01, NULL);
			}
		}

		XPos += Font.CharWidth + Font.CharSpacing;
	}

	Font.ScrollX -= 4;

	if (Font.ScrollX < -Font.Length)
	{
		Font.ScrollX = WIDTH;
	}
}


#endif /* SineScroller_H */