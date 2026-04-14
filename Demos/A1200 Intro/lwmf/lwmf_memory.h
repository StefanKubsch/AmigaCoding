#ifndef LWMF_MEMORY_H
#define LWMF_MEMORY_H

static APTR lwmf_AllocCpuMem(ULONG Size, ULONG Flags)
{
	APTR Ptr = AllocMem(Size, MEMF_FAST | Flags);

	if (!Ptr)
	{
		Ptr = AllocMem(Size, MEMF_ANY | Flags);
	}

	return Ptr;
}


#endif /* LWMF_MEMORY_H */