#ifndef LWMF_HARDWARE_H
#define LWMF_HARDWARE_H

#include <hardware/custom.h>

struct Custom* HardwareCustom = NULL;

void ForcedWaitBlit(void)
{
	while (HardwareCustom->dmaconr & DMAF_BLTDONE)
	{
	}
}

void WaitVBeam(ULONG Line)
{
	ULONG VPos = 0;
	Line *= 0x100;

	while ((VPos & 0x1FF00) != Line)
	{
		VPos = *(ULONG*)0xDFF004;
	}
}

#endif /* LWMF_HARDWARE_H */