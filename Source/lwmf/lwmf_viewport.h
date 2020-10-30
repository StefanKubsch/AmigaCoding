#ifndef LWMF_VIEWPORT_H
#define LWMF_VIEWPORT_H

BOOL lwmf_CreateViewPort(const ULONG Width, const ULONG Height, const int NumberOfBitPlanes, const int NumberOfColors);
void lwmf_UpdateViewPort(void);
void lwmf_CleanupViewPort(void);

struct View view; 
struct ViewPort viewPort;
struct BitMap* BufferBitmap[2];
struct RastPort Buffer[2];
struct RasInfo rasInfo;

// Only long frame copperlists (only non-interlaced mode!)
struct cprlist* LOCpr[2];

struct ColorMap* colorMap = NULL;

BOOL lwmf_CreateViewPort(const ULONG Width, const ULONG Height, const int NumberOfBitPlanes, const int NumberOfColors)
{
	InitView(&view); 

	for (UBYTE i = 0; i < 2; ++i)
	{
		if (!(BufferBitmap[i] = AllocBitMap(Width, Height, NumberOfBitPlanes, BMF_INTERLEAVED | BMF_CLEAR, NULL)))
		{
			lwmf_CleanupViewPort();
			return FALSE;
		}

		InitRastPort(&Buffer[i]);
		Buffer[i].BitMap = BufferBitmap[i];
	}

	rasInfo.RxOffset = 0;
	rasInfo.RyOffset = 0;
	rasInfo.Next = NULL;

	InitVPort(&viewPort);
	view.ViewPort = &viewPort;
	viewPort.RasInfo = &rasInfo;
	viewPort.DWidth = Width;
	viewPort.DHeight = Height;

	colorMap = GetColorMap(NumberOfColors);
	viewPort.ColorMap = colorMap;

	lwmf_UpdateViewPort();	
	LoadView(&view);

	return TRUE;
}

void lwmf_UpdateViewPort(void)
{
	for (UBYTE i = 0; i < 2; ++i)
	{
		rasInfo.BitMap = BufferBitmap[i];
	
		MakeVPort(&view, &viewPort);
		MrgCop(&view);
		
		LOCpr[i] = view.LOFCprList;
		view.LOFCprList = 0;
	}
}

void lwmf_CleanupViewPort(void)
{
	for (UBYTE i = 0; i < 2; ++i)
	{
		FreeCprList(LOCpr[i]);

		if (BufferBitmap[i])
		{
			FreeBitMap(BufferBitmap[i]);
		}
	}
	
	FreeVPortCopLists(&viewPort); 

	if (colorMap)
	{
		FreeColorMap(colorMap);
	}
}


#endif /* LWMF_VIEWPORT_H */