#ifndef LWMF_HARDWARE_H
#define LWMF_HARDWARE_H

//
// Define required registers
//

// CIA
// https://www.amigacoding.com/index.php/CIA_Memory_Map
volatile UBYTE* const CIAA_PRA 		= (volatile UBYTE* const) 0xBFE001;
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

void lwmf_WaitVertBlank(void);

void lwmf_WaitVertBlank(void)
{
	__asm (
		"	.loop: move.l $DFF004, d0\n"\
		"	and.l #$1FF00, d0\n"\
		"	cmp.l #303 << 8, d0\n"\
		"	bne.b .loop\n"\
		"	.loop2: move.l $DFF004, d0\n"\
		"	and.l #$1FF00, d0\n"\
		"	cmp.l #303 << 8, d0\n"\
		"	beq.b .loop2\n"\
	);
}


#endif /* LWMF_HARDWARE_H */