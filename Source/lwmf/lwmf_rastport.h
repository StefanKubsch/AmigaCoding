#ifndef LWMF_RASTPORT_H
#define LWMF_RASTPORT_H

struct RastPort RenderPort;

// Some needed buffers for Area operations
UBYTE* TmpRasBuffer = NULL;
UBYTE* AreaBuffer = NULL;

BOOL lwmf_CreateRastPort(const int NumberOfVertices, const int AreaWidth, const int AreaHeight, const int ClearColor);
void lwmf_CleanupRastPort(void);

BOOL lwmf_CreateRastPort(const int NumberOfVertices, const int AreaWidth, const int AreaHeight, const int ClearColor)
{
	InitRastPort(&RenderPort);

	struct TmpRas tmpRas;
	struct AreaInfo areaInfo;

	const ULONG RasSize = AreaHeight * (AreaWidth + 15) >> 3&0xFFFE;

	if (!(TmpRasBuffer = AllocVec(RasSize, MEMF_CHIP | MEMF_CLEAR)))
	{
		lwmf_CleanupRastPort();
		return FALSE;
	}

	InitTmpRas(&tmpRas, TmpRasBuffer, RasSize);
	RenderPort.TmpRas = &tmpRas;

	// We need to allocate 5bytes per vertex
	if (!(AreaBuffer = AllocVec(5 * NumberOfVertices, MEMF_CHIP | MEMF_CLEAR)))
	{
		lwmf_CleanupRastPort();
		return FALSE;
	}

	InitArea(&areaInfo, AreaBuffer, NumberOfVertices);
	RenderPort.AreaInfo = &areaInfo;

	// Inital clear
	SetRast(&Screen->RastPort, ClearColor);

	return TRUE;
}

void lwmf_CleanupRastPort(void)
{
	if (TmpRasBuffer)
	{
		FreeVec(TmpRasBuffer);
		RenderPort.TmpRas = NULL;
	}

	if (AreaBuffer)
	{
		FreeVec(AreaBuffer);
		RenderPort.AreaInfo = NULL;
	}
}


#endif /* LWMF_RASTPORT_H */