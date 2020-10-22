#ifndef LWMF_HARDWARE_H
#define LWMF_HARDWARE_H

// CIA-A for check if mouse button is pressed
// Use Port Register A 0xBFE001
volatile UBYTE* const CIAA_PRA 		= (volatile UBYTE* const) 0xBFE001;
// Set bit 6 (Port 0 fire button)
const LONG PRA_FIR0 = 1L << 6;

// DMA control register
volatile UWORD* const DMACON 		= (volatile UWORD* const) 0xDFF096;
volatile UWORD* const DMACONR 		= (volatile UWORD* const) 0xDFF002;
// Interrupt request register
volatile UWORD* const INTREQ 		= (volatile UWORD* const) 0xDFF09C;
volatile UWORD* const INTREQR 		= (volatile UWORD* const) 0xDFF01E;
// Interrupt enable register
volatile UWORD* const INTENA 		= (volatile UWORD* const) 0xDFF09A;
volatile UWORD* const INTENAR 		= (volatile UWORD* const) 0xDFF01C;
// Audio/Disk control register
volatile UWORD* const ADKCON 		= (volatile UWORD* const) 0xDFF09E;
volatile UWORD* const ADKCONR 		= (volatile UWORD* const) 0xDFF010;
// Copper
volatile ULONG* const COP1LC 		= (volatile ULONG* const) 0xDFF080;
// VPOS
volatile UWORD* const VPOSR       	= (volatile UWORD* const) 0xDFF004;
volatile UBYTE* const VPOSR_LOW   	= (volatile UBYTE* const) 0xDFF005;
volatile UWORD* const VPOSHR      	= (volatile UWORD* const) 0xDFF006;
volatile UBYTE* const VPOSHR_HIGH 	= (volatile UBYTE* const) 0xDFF006;
volatile UBYTE* const VPOSHR_LOW  	= (volatile UBYTE* const) 0xDFF007;
// Misc
volatile ULONG* const COLOR 		= (volatile ULONG* const) 0xDFF180;

void lwmf_WaitFrame(void);

void lwmf_WaitFrame(void) 
{
	while (*VPOSHR_HIGH != 0x2A)
	{
        while (*VPOSR_LOW & 1)
		{

		}
    }

    while (*VPOSHR_HIGH != 0x2A)
	{

	}
}


#endif /* LWMF_HARDWARE_H */