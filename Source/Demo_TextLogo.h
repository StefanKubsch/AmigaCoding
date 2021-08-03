#ifndef TextLogo_H
#define TextLogo_H


//***************************************
//* Simple text logo         	   		*
//*								   		*
//* (C) 2020-2021 by Stefan Kubsch      *
//***************************************

struct lwmf_Image* LogoBitmap = NULL;

// Create two sintabs for a lissajous figure
// for (UBYTE i = 0; i < 64; ++i)
// {
//		LogoSinTabX[i] = 70 + (UBYTE)(sin(0.1f * (float)i) * 60.0f);
//		LogoSinTabY[i] = 100 + (UBYTE)(sin(0.2f * (float)i) * 40.0f);
// }

UBYTE LogoSinTabX[64] =
{
	70,75,81,87,93,98,103,108,113,116,120,123,125,127,129,129,129,129,128,126,124,121,118,114,110,105,100,95,
	90,84,78,72,67,61,55,49,44,39,34,29,25,21,18,16,13,12,11,11,11,12,13,15,17,21,24,28,33,37,43,48,54,60,66,71
};

UBYTE LogoSinTabY[64] =
{
	100,107,115,122,128,133,137,139,139,138,136,132,127,120,113,105,98,90,83,76,70,66,62,61,61,62,65,70,75,82,89,97,
	104,112,119,126,131,135,138,139,139,137,134,129,123,116,108,100,94,86,79,73,67,64,61,61,61,64,68,73,79,86,94,101
};

BOOL Init_TextLogo(void)
{
	if (!(LogoBitmap = lwmf_LoadImage("gfx/Logo.iff")))
	{
		return FALSE;
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