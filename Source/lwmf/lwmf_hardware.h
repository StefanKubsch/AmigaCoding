#ifndef LWMF_HARDWARE_H
#define LWMF_HARDWARE_H

void lwmf_WaitBlit(void);
void lwmf_WaitVBeam(ULONG Line);

void lwmf_WaitBlit(void)
{
	while (custom->dmaconr & DMAF_BLTDONE)
	{
	}
}

void lwmf_WaitVBeam(ULONG Line)
{
	ULONG VPos = 0;
	Line *= 0x100;

	while ((VPos & 0x1FF00) != Line)
	{
		VPos = *(ULONG*)0xDFF004;
	}
}


#endif /* LWMF_HARDWARE_H */