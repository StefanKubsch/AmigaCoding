#ifndef TextLogo_H
#define TextLogo_H


//***************************************
//* Simple text logo         	   		*
//*								   		*
//* (C) 2020-2021 by Stefan Kubsch      *
//***************************************

#include <math.h>

struct lwmf_Image* LogoBitmap = NULL;

UBYTE LogoSinTabY[64];
UBYTE LogoSinTabX[64];

BOOL Init_TextLogo(void)
{
	if (!(LogoBitmap = lwmf_LoadImage("gfx/Logo.iff")))
	{
		return FALSE;
	}

	// Create two sintabs for a lissajous figure
	for (UBYTE i = 0; i < 64; ++i)
	{
		LogoSinTabX[i] = 70 + (UBYTE)(sin(0.1f * (float)i) * 60.0f);
		LogoSinTabY[i] = 100 + (UBYTE)(sin(0.2f * (float)i) * 40.0f);
	}

	return TRUE;
}

void Draw_TextLogo(void)
{
	static UBYTE SinTabCount = 0;

	// Size of logo = 192x46 starting at position 0,0
	// Size of whole image = 320x256

	// WidthInWords = (Width of Logo / 16) * NumberOfBitPlanes * 2
	// (192 / 16) * 3 * 2 = 72

	// SourceModulo = BytesPerRow - (WidthInWord * 2)
	// BytesPerRow = Width in bytes * NumberOfBitplanes = 40 * 3 = 120
	// 120 - (72 * 2) = -24

	lwmf_BlitTile((long*)LogoBitmap->Image->Planes[0], -24, 0, (long*)RenderPort.BitMap->Planes[0], LogoSinTabX[SinTabCount], LogoSinTabY[SinTabCount], 72, 46);

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