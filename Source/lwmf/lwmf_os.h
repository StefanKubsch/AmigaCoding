#ifndef LWMF_OS_H
#define LWMF_OS_H

// Some stuff needed for OS takeover
struct View* OldView = NULL;
struct copinit* OldCopperInit = NULL;
UWORD Old_dmacon = 0;
UWORD Old_intena = 0;
UWORD Old_adkcon = 0;
UWORD Old_intreq = 0;

void lwmf_TakeOverOS(void);
void lwmf_ReleaseOS(void);

void lwmf_TakeOverOS(void)
{
	// Set task priority
	SetTaskPri(FindTask(NULL), 20);

	// Disable task rescheduling
	Forbid();

	// Save current view
	OldView = GfxBase->ActiView;
	// Save current copperlist
	OldCopperInit = GfxBase->copinit;
	
    // Reset view (clear anything)
	LoadView(NULL);

    WaitTOF();
    WaitTOF();

	// Save custom registers
	Old_dmacon = custom->dmaconr;
	Old_intena = custom->intenar;
	Old_adkcon = custom->adkconr;
	Old_intreq = custom->intreqr;

	// Disable all interrupts
	Disable();

	// Set DMA

	// F    SET/CLR  0=clear, 1=set bits that are set to 1 below
	// E    BBUSY    Blitter busy status bit (read only)
	// D    BZERO    Blitter logic zero status bit. (read only)
	// C    -        Reserved/Unused
	// B    -        Reserved/Unused
	// A    BLTPRI   Blitter priority, 0=give every 4th cycle to CPU
	// 9    DMAEN    Enable all DMA below
	// 8    BPLEN    Bit plane DMA
	// 7    COPEN    Copper DMA
	// 6    BLTEN    Blitter DMA
	// 5    SPREN    Sprite DMA
	// 4    DSKEN    Disk DMA
	// 3    AUD3EN   Audio channel 3 DMA
	// 2    AUD2EN   Audio channel 2 DMA
	// 1    AUD1EN   Audio channel 1 DMA
	// 0    AUD0EN   Audio channel 0 DMA

	// Set all DMACON bits to zero
	// To set this, you need also to disable bit 15 (SET/CLR)
	// So its: 0111111111111111 or 0x7FFF
	custom->dmacon = 0x7FFF;

	// Set 10, 7, 6
	// To set these, you need also to set bit 15 (SET/CLR)
	// So its: 1000010011000000 or 0x84C0
	// Or use the macros defined in "hardware/dmabits.h":
	custom->dmacon = 0x84C0;
}

void lwmf_ReleaseOS(void)
{
	// Restore custom registers
	custom->dmacon = 0x7FFF;
	custom->intena = 0x7FFF;
	custom->adkcon = 0x7FFF;
	custom->intreq = 0x7FFF;

	custom->dmacon = Old_dmacon;
	custom->intena = Old_intena;
	custom->adkcon = Old_adkcon;
	custom->intreq = Old_intreq;

	// Enable interrupts
	Enable();
	
	// Restore previously saved copperlist
	custom->cop1lc = (ULONG)OldCopperInit;
	OldCopperInit = NULL;

	// Restore previously saved vire
	LoadView(OldView);
	OldView = NULL;

	WaitTOF();
	WaitTOF();

	// Enable task rescheduling
	Permit();
}


#endif /* LWMF_OS_H */