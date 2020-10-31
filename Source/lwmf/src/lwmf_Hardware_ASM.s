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
.loop2:                             ; Second check for A4000 compatibility
	move.l  VPOSR,d0
	and.l   #$1FF00,d0
	cmp.l   #303<<8,d0
	beq.b   .loop2
	rts

	public	_lwmf_WaitVertBlank
	
;
; void lwmf_ClearMem(__reg("a0") UBYTE* Address, __reg("d0") long NumberOfBytes);
;

_lwmf_ClearMem:
    move.l  a0,BLTDPTH  		; Set up the D pointer to the region to clear
    clr.w   BLTDMOD   		    ; Clear the D modulo (don't skip no bytes)
    asr.l   #1,d0           	; Get number of words from number of bytes
    clr.w   BLTCON1     		; No special modes
    move.w  #DEST,BLTCON0       ; only enable destination
    moveq   #$3F,d1         	; Mask out mod 64 words
    and.w   d0,d1
    beq     .dorest          	; none?  good, do one blit
    sub.l   d1,d0           	; otherwise remove remainder
    or.l    #$40,d1         	; set the height to 1, width to n
    move.w  d1,BLTSIZE  				
.dorest:
    move.w  #$ffc0,d1       	; look at some more upper bits
    and.w   d0,d1           	; extract 10 more bits
    beq     .dorest2         				
    sub.l   d1,d0           	; pull of the ones we're doing here
    bsr     _lwmf_WaitBlitter        		
    move.w  d1,BLTSIZE  				
.dorest2:
    swap    d0              	; more?
    beq     .ready            				
    clr.w   d1              	; do a 1024x64 word blit (128K)
.work:
    bsr     _lwmf_WaitBlitter        		
    move.w  d1,BLTSIZE  		; and again, blit
    subq.w  #1,d0           				
    bne     .work          				
.ready:
    rts

	public	_lwmf_ClearMem