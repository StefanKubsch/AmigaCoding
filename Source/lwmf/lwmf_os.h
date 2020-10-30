#ifndef LWMF_OS_H
#define LWMF_OS_H

void lwmf_TakeOverOS(void);
void lwmf_ReleaseOS(void);

// Some stuff needed for OS takeover
struct View* OldView = NULL;
UWORD Old_DMACON = 0;
UWORD Old_INTREQ = 0;
UWORD Old_INTENA = 0;
UWORD Old_ADKCON = 0;

void lwmf_TakeOverOS(void)
{
	// Set task priority
	SetTaskPri(FindTask(NULL), 20);

	// Disable task rescheduling
	Forbid();

	// Save current view
	OldView = GfxBase->ActiView;
	
    // Reset view (clear anything)
	LoadView(NULL);
    WaitTOF();
    WaitTOF();

	lwmf_WaitBlitter();

	Old_DMACON = *DMACONR;
	Old_INTREQ = *INTREQR;
	Old_INTENA = *INTENAR;
	Old_ADKCON = *ADKCONR;

    // BIT#  FUNCT  LEVEL DESCRIPTION
    // ----  ------ ----- ----------------------------------
    //  15    SET/CLR     Set/clear control bit. Determines if
    //                    bits written with a 1 get set or
    //                    cleared. Bits written with a zero
    //                    are always unchanged.
    //  14    INTEN       Master interrupt (enable only,
    //                    no request)
    //  13    EXTER   6   External interrupt
    //  12    DSKSYN  5   Disk sync register ( DSKSYNC )
    //                    matches disk data
    //  11    RBF     5   Serial port receive buffer full
    //  10    AUD3    4   Audio channel 3 block finished
    //  09    AUD2    4   Audio channel 2 block finished
    //  08    AUD1    4   Audio channel 1 block finished
    //  07    AUD0    4   Audio channel 0 block finished
    //  06    BLIT    3   Blitter finished
    //  05    VERTB   3   Start of vertical blank
    //  04    COPER   3   Copper
    //  03    PORTS   2   I/O ports and timers
    //  02    SOFT    1   Reserved for software-initiated
    //                    interrupt
    //  01    DSKBLK  1   Disk block finished
    //  00    TBE     1   Serial port transmit buffer empty
	
	// Clear all pending interrupt requests
	*INTREQ = 0x7FFF;
	
	// Set 1101000001111110 = 0xD07E
	// *INTENA = 0xD07E;
	// *INTREQ = 0xD07E;

	// BIT#  FUNCTION    DESCRIPTION
    // ----  ---------   -----------------------------------
	//  15    SET/CLR     Set/clear control bit. Determines
    //                    if bits written with a 1 get set or
    //                    cleared.  Bits written with a zero
    //                    are unchanged.
    //  14    BBUSY       Blitter busy status bit (read only)
    //  13    BZERO       Blitter logic  zero status bit
    //                    (read only).
    //  12    X
    //  11    X
    //  10    BLTPRI      Blitter DMA priority
    //                    (over CPU micro) (also called
    //                    "blitter nasty") (disables /BLS
    //                    pin, preventing micro from
    //                    stealing any bus cycles while
    //                    blitter DMA is running).
    //  09    DMAEN       Enable all DMA below
    //  08    BPLEN       Bitplane DMA enable
    //  07    COPEN       Copper DMA enable
    //  06    BLTEN       Blitter DMA enable
    //  05    SPREN       Sprite DMA enable
    //  04    DSKEN       Disk DMA enable
    //  03    AUD3EN      Audio channel 3 DMA enable
    //  02    AUD2EN      Audio channel 2 DMA enable
    //  01    AUD1EN      Audio channel 1 DMA enable
    //  00    AUD0EN      Audio channel 0 DMA enable
	
	// Set all bits to zero
	*DMACON = 0x7FFF;
	
	// Set 1000001111000000 = 0x83C0
	*DMACON = 0x83C0;
}

void lwmf_ReleaseOS(void)
{
	lwmf_WaitBlitter();

	// Restore custom registers
	*DMACON = 0x7FFF;
	*DMACON = Old_DMACON | 0x8000;
	*INTREQ = 0x7FFF;
	*INTREQ = Old_INTREQ | 0x8000;
	*INTENA = 0x7FFF;
	*INTENA = Old_INTENA | 0x8000;
	*ADKCON = 0x7FFF;
	*ADKCON = Old_ADKCON | 0x8000;

	// Restore previously saved view
	LoadView(OldView);
	WaitTOF();
	WaitTOF();
   	OldView = NULL;

	// Enable task rescheduling
	Permit();
}


#endif /* LWMF_OS_H */