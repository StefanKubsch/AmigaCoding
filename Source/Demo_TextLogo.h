#ifndef TextLogo_H
#define TextLogo_H


//**********************************
//* Simple text logo         	   *
//*								   *
//* (C) 2020 by Stefan Kubsch      *
//**********************************

struct lwmf_Image* LogoBitmap = NULL;
WORD SrcModulo = 0;
WORD WidthInWords = 0;

UWORD LogoSinTabY[64];
UWORD LogoSinTabX[64];

BOOL Init_TextLogo(void)
{
	if (!(LogoBitmap = lwmf_LoadImage("gfx/logo.iff")))
	{
		return FALSE;
	}

	WidthInWords = (176 >> 4) * (LogoBitmap->Image->Depth << 1);
	SrcModulo = (LogoBitmap->Image->BytesPerRow) - (WidthInWords << 1);

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

	lwmf_BlitTile((long*)LogoBitmap->Image->Planes[0], SrcModulo, 0, (long*)RenderPort.BitMap->Planes[0], LogoSinTabX[SinTabCount], LogoSinTabY[SinTabCount], WidthInWords, 47);

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