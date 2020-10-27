#ifndef LWMF_VIEWPORT_H
#define LWMF_VIEWPORT_H

struct View view; 
struct ViewPort viewPort;
struct BitMap* BufferBitmap1 = NULL;
struct BitMap* BufferBitmap2 = NULL;
struct RastPort RastPort1;
struct RastPort RastPort2;
struct RasInfo rasInfo;

// Only long frame copperlists (only non-interlaced mode!)
struct cprlist* LOCpr1 = NULL;
struct cprlist* LOCpr2 = NULL;

struct ColorMap* colorMap = NULL;

BOOL lwmf_CreateViewPort(const ULONG Width, const ULONG Height, const int NumberOfBitPlanes);
void lwmf_UpdateViewPort(void);
void lwmf_CleanupViewPort(void);

BOOL lwmf_CreateViewPort(const ULONG Width, const ULONG Height, const int NumberOfBitPlanes)
{
	InitView(&view); 

	if (!(BufferBitmap1 = AllocBitMap(Width, Height, NumberOfBitPlanes, BMF_INTERLEAVED | BMF_CLEAR, NULL)))
	{
		return FALSE;
	}

	if (!(BufferBitmap2 = AllocBitMap(Width, Height, NumberOfBitPlanes, BMF_INTERLEAVED | BMF_CLEAR, NULL)))
	{
		lwmf_CleanupViewPort();
		return FALSE;
	}

	InitRastPort(&RastPort1);
	RastPort1.BitMap = BufferBitmap1;
	
	InitRastPort(&RastPort2);
	RastPort2.BitMap = BufferBitmap2;
	
	rasInfo.RxOffset = 0;
	rasInfo.RyOffset = 0;
	rasInfo.Next = NULL;

	InitVPort(&viewPort);
	view.ViewPort = &viewPort;
	viewPort.RasInfo = &rasInfo;
	viewPort.DWidth = Width;
	viewPort.DHeight = Height;

	colorMap = GetColorMap(lwmf_IntPow(2, NumberOfBitPlanes));
	viewPort.ColorMap = colorMap;

	lwmf_UpdateViewPort();	
	LoadView(&view);

	return TRUE;
}

void lwmf_UpdateViewPort(void)
{
	rasInfo.BitMap = BufferBitmap1;
	
	MakeVPort(&view, &viewPort);
	MrgCop(&view);
	
	LOCpr1 = view.LOFCprList;
		
	view.LOFCprList = 0;
	
	rasInfo.BitMap = BufferBitmap2;
	
	MakeVPort(&view, &viewPort);
	MrgCop(&view);
	
	LOCpr2 = view.LOFCprList;
}

void lwmf_CleanupViewPort(void)
{
	FreeCprList(LOCpr1);
	FreeCprList(LOCpr2);
	
	FreeVPortCopLists(&viewPort); 

	if (colorMap)
	{
		FreeColorMap(colorMap);
	}

	if (BufferBitmap1)
	{
		FreeBitMap(BufferBitmap1);
	}

	if (BufferBitmap2)
	{
		FreeBitMap(BufferBitmap2);
	}
}


#endif /* LWMF_VIEWPORT_H */