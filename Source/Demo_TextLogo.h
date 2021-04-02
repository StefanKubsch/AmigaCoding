#ifndef TextLogo_H
#define TextLogo_H


//***************************************
//* Simple text logo         	   		*
//*								   		*
//* (C) 2020-2021 by Stefan Kubsch      *
//***************************************

#include <stdio.h>

struct lwmf_Image* LogoBitmap = NULL;
WORD SrcModulo = 0;
WORD WidthInWords = 0;

UWORD LogoSinTabY[64];
UWORD LogoSinTabX[64];

BOOL Init_TextLogo(void)
{
	if (!(LogoBitmap = lwmf_LoadImage("gfx/Logo.iff")))
	{
		return FALSE;
	}

	// Temporary debug stuff
	printf("Test of own blitting routine\nImage data\n\n");
	printf("Bitmap width : %d\nBitmap height : %d\nBitmap depth : %d\nBytes per row : %d\n", LogoBitmap->Width, LogoBitmap->Height, LogoBitmap->Image->Depth, LogoBitmap->Image->BytesPerRow);

	WidthInWords = (192 / 16) * LogoBitmap->Image->Depth * 2;
	SrcModulo = LogoBitmap->Image->BytesPerRow - (WidthInWords * 2);

	// Temporary debug stuff
	printf("Width in words : %d\nSource Modulo : %d\n", WidthInWords, SrcModulo);

	// Create two sintabs for a lissajous figure
	for (UBYTE i = 0; i < 64; ++i)
	{
		LogoSinTabX[i] = 70 + (UWORD)(sin(0.1f * (float)i) * 60.0f);
		LogoSinTabY[i] = 100 + (UWORD)(sin(0.2f * (float)i) * 40.0f);
	}

	return TRUE;
}

void Draw_TextLogo(void)
{
	static UBYTE SinTabCount = 0;

	lwmf_BlitTile((long*)LogoBitmap->Image->Planes[0], SrcModulo, 0, (long*)RenderPort.BitMap->Planes[0], LogoSinTabX[SinTabCount], LogoSinTabY[SinTabCount], WidthInWords, 46);

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


#endif /* TextLogo_H */