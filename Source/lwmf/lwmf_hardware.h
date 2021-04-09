#ifndef LWMF_HARDWARE_H
#define LWMF_HARDWARE_H

//
// Define required registers
//

// CIA
// https://www.amigacoding.com/index.php/CIA_Memory_Map
volatile UBYTE* const CIAA_PRA 		= (volatile UBYTE* const) 0xBFE001;
// Copper
volatile ULONG* const COP1LC 		= (volatile ULONG* const) 0xDFF080;
// Mouse pointer (Sprite 0 DMA pointer)
volatile UWORD* const SPR0PTH		= (volatile UWORD* const) 0xDFF120;
volatile UWORD* const SPR0PTL		= (volatile UWORD* const) 0xDFF122;
// Misc
volatile UWORD* const COLOR00		= (volatile UWORD* const) 0xDFF180;

// Define a "blank" sprite for mouse pointer
// "__chip" tells vbcc to store an array or variable in Chipmem!
__chip UWORD BlankMousePointer[4] = 
{
	0x0000, 0x0000,
	0x0000, 0x0000
};

BOOL FastCPUFlag = FALSE;

void lwmf_CheckCPU(void)
{
	struct ExecBase* SysBase = *((struct ExecBase**)4L);

	// Check if CPU is a 68020, 030, 040, 060 (this is the "0x80")
	// If yes, we can calculate more stuff...
	if (SysBase->AttnFlags & AFF_68020 || SysBase->AttnFlags & AFF_68030 || SysBase->AttnFlags & AFF_68040 || SysBase->AttnFlags & 0x80)
	{
		FastCPUFlag = TRUE;
	}
}


#endif /* LWMF_HARDWARE_H */