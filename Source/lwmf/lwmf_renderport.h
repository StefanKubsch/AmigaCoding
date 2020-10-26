#ifndef LWMF_RENDERPORT_H
#define LWMF_RENDERPORT_H

struct RastPort RenderPort;

// Some needed buffers for Area operations
UBYTE* TmpRasBuffer = NULL;
UBYTE* AreaBuffer = NULL;

BOOL lwmf_CreateRenderPort(const UWORD NumberOfVertices, const UWORD AreaWidth, const UWORD AreaHeight);
void lwmf_CleanupRenderPort(void);

BOOL lwmf_CreateRenderPort(const UWORD NumberOfVertices, const UWORD AreaWidth, const UWORD AreaHeight)
{
	InitRastPort(&RenderPort);

	struct TmpRas tmpRas;
	struct AreaInfo areaInfo;

	const ULONG RasSize = AreaHeight * (AreaWidth + 15) >> 3&0xFFFE;

	if (!(TmpRasBuffer = AllocVec(RasSize, MEMF_CHIP | MEMF_CLEAR)))
	{
		lwmf_CleanupRenderPort();
		lwmf_CloseLibraries();
		return FALSE;
	}

	InitTmpRas(&tmpRas, TmpRasBuffer, RasSize);
	RenderPort.TmpRas = &tmpRas;

	// We need to allocate 5bytes per vertex
	if (!(AreaBuffer = AllocVec(5 * NumberOfVertices, MEMF_CHIP | MEMF_CLEAR)))
	{
		lwmf_CleanupRenderPort();
		lwmf_CloseLibraries();
		return FALSE;
	}

	InitArea(&areaInfo, AreaBuffer, NumberOfVertices);
	RenderPort.AreaInfo = &areaInfo;

	return TRUE;
}

void lwmf_CleanupRenderPort(void)
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


#endif /* LWMF_RENDERPORT_H */