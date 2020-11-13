#ifndef TextLogo_H
#define TextLogo_H


//**********************************
//* Simple text logo         	   *
//*								   *
//* (C) 2020 by Stefan Kubsch      *
//**********************************

#include <string.h>

BOOL Init_TextLogo(void);
void Cleanup_TextLogo(void);
void Draw_TextLogo(void);

struct Logofont
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
	WORD SrcModulo;
	WORD DstModulo;
	WORD BlitSize;
} TextFont;

BOOL Init_TextLogo(void)
{
	// ScrollFont.bsh is an ILBM (IFF) file
	// In this case it´s a "brush", made with Personal Paint on Amiga - a brush is smaller in size
	// The original IFF ScrollFont.iff in included in gfx
	if (!(TextFont.FontBitmap = lwmf_LoadImage("gfx/scrollfont.bsh")))
	{
		return FALSE;
	}

	// Text & Font settings
	TextFont.Text = "DEEP4";
	TextFont.CharMap = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!-,+?*()";
	TextFont.CharWidth = 15;
	TextFont.CharHeight = 20;
	TextFont.CharSpacing = 1;
	TextFont.CharOverallWidth = TextFont.CharWidth + TextFont.CharSpacing;
	TextFont.TextLength = strlen(TextFont.Text);
	TextFont.CharMapLength = strlen(TextFont.CharMap);
	TextFont.SrcModulo = (TextFont.FontBitmap->Width >> 3) - 1;
	TextFont.DstModulo = ((SCREENWIDTH >> 3) * NUMBEROFBITPLANES) - 1;
	TextFont.BlitSize = (TextFont.CharHeight << 6) + 1;

	if (!(TextFont.Map = AllocVec(sizeof(WORD) * TextFont.TextLength, MEMF_ANY | MEMF_CLEAR)))
	{
		return FALSE;
	}

	// Pre-calc char positions in map
	for (UWORD i = 0; i < TextFont.TextLength; ++i)
	{
		TextFont.Map[i] = 9999;

		for (UWORD j = 0, MapPos = 0; j < TextFont.CharMapLength; ++j)
		{
			if (*(TextFont.Text + i) == *(TextFont.CharMap + j))
			{
				TextFont.Map[i] = MapPos;
				break;
			}

			MapPos += 2;
		}

		// char not found, space
		if (TextFont.Map[i] == 9999)
		{
			TextFont.Map[i] = -1;
		}
	}

	return TRUE;
}

void Cleanup_TextLogo(void)
{
	if (TextFont.FontBitmap)
	{
		lwmf_DeleteImage(TextFont.FontBitmap);
	}

	if (TextFont.Map)
	{
		FreeVec(TextFont.Map);
	}
}

void Draw_TextLogo(void)
{
	WORD XPos = 175;

	for (UWORD i = 0; i < TextFont.TextLength; ++i)
	{
		lwmf_BlitTile((long*)TextFont.FontBitmap->Image->Planes[0], TextFont.SrcModulo, TextFont.Map[i], (long*)RenderPort.BitMap->Planes[0], TextFont.DstModulo, XPos, 234, TextFont.BlitSize);
		XPos += TextFont.CharOverallWidth << 1;
	}
}


#endif /* TextLogo_H */