; Various assembler functions for lwmf
; Code is compatible with Motorola syntax as provided by vbcc

; Defines

CUSTOM		    = $DFF000   ; Base address of custom registers
DMACONR         = $DFF002   ; DMA control (and blitter status) read
VPOSR           = $DFF004   ; Read vert most sig. bits (and frame flop)
BLTCON0 	    = $DFF040   ; Blitter control reg 0
BLTCON1 	    = $DFF042   ; Blitter control reg 1
BLTDPTH		    = $DFF054   ; Blitter pointer to destination D (high 5 bits)
BLTDPTL         = $DFF056   ; Blitter pointer to destination D (low 15 bits)
BLTDMOD 	    = $DFF066   ; Blitter modulo for destination D
BLTSIZE 	    = $DFF058   ; Blitter start and size (win/width, height)

DEST 		    = $100      ; Blitter control register / destination

DMAB_BLTDONE    = 14        ; DMACONR bit 14 - blitter busy flag

;
; void _lwmf_WaitBlitter(void)
;

_lwmf_WaitBlitter:
    btst.b  #DMAB_BLTDONE-8,DMACONR 		; check against DMACONR
.waitblit:                                  ; check twice, bug in A1000
    btst.b 	#DMAB_BLTDONE-8,DMACONR 		
    bne 	.waitblit
    rts

	public _lwmf_WaitBlitter

;
; void _lwmf_WaitVertBlank(void)
;

_lwmf_WaitVertBlank:
.loop: 
    move.l  VPOSR,d0
	and.l   #$1FF00,d0
	cmp.l   #303<<8,d0
	bne.b   .loop
.loop2:                         ; Second check for A4000 compatibility
	move.l  VPOSR,d0
	and.l   #$1FF00,d0
	cmp.l   #303<<8,d0
	beq.b   .loop2
	rts

	public _lwmf_WaitVertBlank
	
;
; void lwmf_ClearMem(__reg("a0") long* Address, __reg("d0") long NumberOfBytes);
;

_lwmf_ClearMem:
    lsr.l   #5,d0               ; Shift right by 5 -> Division by 32
    sub.l   #1,d0
    move.l  #0,d1
.loop:
    move.l  d1,(a0)+
    move.l  d1,(a0)+
    move.l  d1,(a0)+
    move.l  d1,(a0)+
    move.l  d1,(a0)+
    move.l  d1,(a0)+
    move.l  d1,(a0)+
    move.l  d1,(a0)+
    dbra    d0,.loop
    rts

    public _lwmf_ClearMem