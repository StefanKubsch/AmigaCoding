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
	int CharWidth;
	int CharHeight;
	int CharSpacing;
	int TextLength;
	int CharMapLength;
	int Length;
	int ScrollX;
} Font;

int ScrollSinTab[320];

BOOL Init_SineScroller(void)
{
	// Generate sinus table
	for (int i = 0; i < 320; ++i)
	{
		ScrollSinTab[i] = (int)(sin(0.03f * i) * 70.0f);
	}

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

	return TRUE;
}

void Cleanup_SineScroller(void)
{
	if (Font.FontBitmap)
	{
		lwmf_DeleteImage(Font.FontBitmap);
	}
}

void Draw_SineScroller(void)
{
	for (int i = 0, XPos = Font.ScrollX; i < Font.TextLength; ++i)
	{
		for (int j = 0, CharX = 0; j < Font.CharMapLength; ++j)
		{
			if (*(Font.Text + i) == *(Font.CharMap + j))
			{
				for (int x1 = 0, x = CharX; x < CharX + Font.CharWidth; ++x1, ++x)
				{
					const int TempPosX = XPos + x1;

					if ((unsigned int)TempPosX < WIDTH)
					{
						BltBitMap(Font.FontBitmap->Image, x, 0, RenderPort.BitMap, TempPosX, 120 + ScrollSinTab[TempPosX], 1, Font.CharHeight, 0xC0, 0x07, NULL);
					}
				}

				break;
			}

			if (XPos >= WIDTH)
			{
				break;
			}

			CharX += Font.CharWidth + Font.CharSpacing;
		}

		XPos += Font.CharWidth + Font.CharSpacing;
	}

	Font.ScrollX -= 5;

	if (Font.ScrollX < -Font.Length)
	{
		Font.ScrollX = WIDTH;
	}
}


#endif /* SineScroller_H */