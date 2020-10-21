#ifndef LWMF_HARDWARE_H
#define LWMF_HARDWARE_H

// CIA-A for check if mouse button is pressed
// Use Port Register 1 0xBFE001
volatile UBYTE* CIAA_PRA = (volatile UBYTE*) 0xBFE001;
// Set bit 6 (Port 0 fire button)
const LONG PRA_FIR0 = 1L << 6;

void lwmf_WaitVBeam(ULONG Line);

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