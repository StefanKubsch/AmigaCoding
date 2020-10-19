#ifndef LWMF_HARDWARE_H
#define LWMF_HARDWARE_H

void lwmf_WaitBlit(void);
void lwmf_WaitVBeam(ULONG Line);

void lwmf_WaitBlit(void)
{
	// This is the correct way to check if the blitter is idle...
	// The additional wait (if) is needed because of some blitter bugs
	// We check DMAF_BLTDONE = 0x4000
	// http://amigadev.elowar.com/read/ADCD_2.1/Includes_and_Autodocs_2._guide/node00CB.html

	if (custom->dmaconr & 0x4000)
	{
	}

	while (custom->dmaconr & 0x4000)
	{
	}
}

void lwmf_WaitVBeam(ULONG Line)
{
	// Read register VPOSR
	ULONG VPos = 0;
	Line *= 0x100;

	while ((VPos & 0x1FF00) != Line)
	{
		VPos = *(ULONG*)0xDFF004;
	}
}


#endif /* LWMF_HARDWARE_H */