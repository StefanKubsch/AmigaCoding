#ifndef LWMF_HARDWARE_H
#define LWMF_HARDWARE_H

// Global symbols for our assembler functions
void lwmf_TakeOverOS(void);
void lwmf_ReleaseOS(void);
void lwmf_WaitVertBlank(void);
void lwmf_WaitBlitter(void);
void lwmf_ClearMem(__reg("a0") long* Address, __reg("d0") long NumberOfBytes);
__reg("d0") ULONG lwmf_Random(void);

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


#endif /* LWMF_HARDWARE_H */