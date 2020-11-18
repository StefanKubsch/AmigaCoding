#ifndef TextLogo_H
#define TextLogo_H


//**********************************
//* Simple text logo         	   *
//*								   *
//* (C) 2020 by Stefan Kubsch      *
//**********************************

struct lwmf_Image* LogoBitmap;
WORD SrcModulo;
WORD WidthInWords;

UWORD LogoSinTabY[64];
UWORD LogoSinTabX[64];

BOOL Init_TextLogo(void)
{
	if (!(LogoBitmap = lwmf_LoadImage("gfx/logo.iff")))
	{
		return FALSE;
	}

	WidthInWords = (176 / 16) * (LogoBitmap->Image->Depth * 2);
	SrcModulo = (LogoBitmap->Image->BytesPerRow) - (WidthInWords * 2);

	// Create two sintabs for a lissajous figure
	for (UBYTE i = 0; i < 64; ++i)
	{
		LogoSinTabY[i] = (UWORD)(sin(0.2f * (float)i) * 40.0f);
		LogoSinTabX[i] = (UWORD)(sin(0.1f * (float)i) * 60.0f);
	}

	return TRUE;
}

void Draw_TextLogo(void)
{
	static UBYTE LogoSinTabCount = 0;

	lwmf_BlitTile((long*)LogoBitmap->Image->Planes[0], SrcModulo, 0, (long*)RenderPort.BitMap->Planes[0], 70 + LogoSinTabX[LogoSinTabCount], 100 + LogoSinTabY[LogoSinTabCount], WidthInWords, 47);

	if (++LogoSinTabCount >= 63)
	{
		LogoSinTabCount = 0;
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