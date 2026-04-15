; Various assembler functions for lwmf
; Code is compatible with Motorola syntax as provided by vbcc
; OCS/68000 compatible (68010 directive required for movec.l vbr,d0 in lwmf_GetVBR)
;
; Coded in 2020-2026 by Stefan Kubsch / Deep4

	machine	68010

	include "lwmf_hardware_regs.i"

; ***************************************************************************************************
; * Functions                                                                                       *
; ***************************************************************************************************

; Some words about registers
;
; a0,a1,d0,d1 are "scratch" registers - you can do what you want with 'em
; All other registers need to be saved before used in a function, and must be restored before returning
;
; Libraries expect their respective base address in a6!
;
; Some words about labels (taken from vasm Manual)
;
; Labels must either start at the first column of a line or have to be terminated by a colon
; (:). In the first case the mnemonic has to be separated from the label by whitespace (not
; required in any case, e.g. with the = directive). A double colon (::) automatically makes
; the label externally visible (refer to xdef).

; **************************************************************************
; * System / Helperfunctions                                               *
; **************************************************************************

;
; long lwmf_GetVBR(void);
;

_lwmf_GetVBR::
        movem.l a5-a6,-(sp)           ; save registers on stack

        move.l  SYSBASE.w,a6          ; get SysBase
        btst    #0,ATTNFLAGS(a6)      ; check for 68010+ cpu
        beq.s   .no_vbr               ; jump if not supported

        lea     .supercode(pc),a5     ; load supervisor code address
        jsr     LVOSupervisor(a6)     ; call supervisor function
        bra.s   .done                 ; skip fallback return

.no_vbr:
        moveq   #0,d0                 ; return 0

.done:
        movem.l (sp)+,a5-a6           ; restore registers
        rts                           ; return

.supercode:
        movec.l vbr,d0                ; get vbr
        rte                           ; return from exception

; **************************************************************************
; * Library handling                                                       *
; **************************************************************************

;
; UWORD lwmf_LoadGraphicsLib(void);
;

_lwmf_LoadGraphicsLib::
	move.l	a6,-(sp)                ; save register on stack
	move.l	EXECBASE.w,a6           ; use exec base address

	lea     gfxlib(pc),a1			; load graphics library name
	moveq   #MINVERSION,d0			; set minimum library version
	jsr     LVOOpenLibrary(a6)		; open graphics library
	move.l  d0,_GfxBase				; store address of GfxBase in variable
	beq.s   .error					; jump if library open failed

	moveq   #0,d0					; return with success
	bra.s   .exit

.error
	clr.l   _GfxBase				; clear GfxBase variable
	moveq   #20,d0					; return with error

.exit
	move.l	(sp)+,a6				; restore register
	rts

;
; void lwmf_CloseLibraries(void);
;

_lwmf_CloseLibraries::
	move.l  a6,-(sp)                ; save register on stack
	move.l  EXECBASE.w,a6           ; use exec base address

	move.l  _GfxBase(pc),a1         ; load GfxBase
	beq.s   .done                   ; skip if not open
	jsr     LVOCloseLibrary(a6)     ; close graphics library
	clr.l   _GfxBase                ; clear GfxBase variable

.done
	move.l  (sp)+,a6                ; restore register
	rts

; **************************************************************************
; * System take over                                                       *
; **************************************************************************

;
; void lwmf_TakeOverOS(void);
;

_lwmf_TakeOverOS::
	move.l	a6,-(sp)                	; save register on stack

	move.w  DMACONR,d0          		; store current CUSTOMREGS registers for later restore
	or.w    #$8000,d0
	move.w  d0,olddma
	move.w  INTENAR,d0
	or.w    #$8000,d0
	move.w  d0,oldintena
	move.w  INTREQR,d0
	or.w    #$8000,d0
	move.w  d0,oldintreq
	move.w  ADKCONR,d0
	or.w    #$8000,d0
	move.w  d0,oldadkcon

	move.l  _GfxBase(pc),a6
	move.l  GFX_ACTIVIEW(a6),oldview    ; store current view
	move.l  GFX_COPINIT(a6),oldcopper  	; store current copperlist
	suba.l  a1,a1                   	; Set a1 to zero
	jsr     LVOLoadView(a6)	        	; LoadView(NULL)
	jsr     LVOWaitTOF(a6)
	jsr     LVOWaitTOF(a6)

	bsr     _lwmf_WaitBlitter        	; wait for any in-progress blit before killing DMA

	move.w  #$7FFF,INTENA       		; disable ALL hardware interrupt enables
	move.w  #$7FFF,INTREQ       		; clear all pending interrupt requests (write twice - hardware quirk)
	move.w  #$7FFF,INTREQ

	move.w  #$7FFF,DMACON       		; clear all DMA channels
	move.w  #DMASET_DEMO,DMACON 		; re-enable bitplane/copper/blitter DMA

	move.l	EXECBASE.w,a6
	jsr     LVOForbid(a6)               ; prevent task switches when ptplayer later re-enables its INTENA bit

	move.l	(sp)+,a6                	; restore register
	rts

;
; void lwmf_ReleaseOS(void);
;

_lwmf_ReleaseOS::
	move.l	a6,-(sp)                    ; save register on stack

	bsr     _lwmf_WaitBlitter           ; wait for any in-progress blit before restoring DMA

	move.w  #$7FFF,DMACON
	move.w  olddma(pc),DMACON
	move.w  #$7FFF,INTREQ               ; clear all pending interrupt requests (write twice - hardware quirk)
	move.w  #$7FFF,INTREQ
	; NOTE: oldintreq is intentionally NOT restored - INTREQ is a status register,
	; not a mask. Writing back stale request bits would artificially re-trigger
	; OS interrupt handlers for events that occurred before TakeOverOS.
	move.w  #$7FFF,INTENA
	move.w  oldintena(pc),INTENA
	move.w  #$7FFF,ADKCON
	move.w  oldadkcon(pc),ADKCON
	move.l  oldcopper(pc),COP1LCH		; restore system copperlist

	move.l  _GfxBase(pc),a6             ; use graphics.library base address
	move.l  oldview(pc),a1              ; restore saved view
	jsr     LVOLoadView(a6)             ; loadView(oldview)
	jsr     LVOWaitTOF(a6)
	jsr     LVOWaitTOF(a6)

	move.l  EXECBASE.w,a6               ; use exec base address
	jsr     LVOPermit(a6)

	move.l	(sp)+,a6                    ; restore register
   	rts

; **************************************************************************
; * Graphics functions                                                     *
; **************************************************************************

;
; void lwmf_OwnBlitter(void);
;
; Direct hardware: enable blitter-nasty mode (CPU yields bus to blitter).
; No OS arbiter needed — lwmf_TakeOverOS has already called Forbid().
;

_lwmf_OwnBlitter::
	move.w  #$8400,DMACON           ; set BLTPRI (blitter nasty)
   	rts

;
; void lwmf_DisownBlitter(void);
;

_lwmf_DisownBlitter::
	move.w  #$0400,DMACON           ; clear BLTPRI (blitter nasty)
   	rts

;
; void lwmf_WaitBlitter(void);
;

_lwmf_WaitBlitter::
	move.l	a6,-(sp)                					; save register on stack
	lea		CUSTOMREGS,a6								; a6 = CUSTOMREGS base for compact addressing

	btst.b  #DMAB_BLITTER,(DMACONR-CUSTOMREGS,a6)       ; already idle? skip nasty mode entirely
	beq.s   .done
	move.w	#$8400,(DMACON-CUSTOMREGS,a6)				; enable blitter nasty
.loop
	btst.b 	#DMAB_BLITTER,(DMACONR-CUSTOMREGS,a6) 		; check blitter busy flag
	bne.s 	.loop
	move.w	#$0400,(DMACON-CUSTOMREGS,a6)				; disable blitter nasty
.done
	move.l	(sp)+,a6       								; restore registers
	rts

;
; void lwmf_WaitVertBlank(void);
;

_lwmf_WaitVertBlank::
.waithigh
    btst.b  #0,VPOSR+1        		; wait until V8 = 1 (line 256+)
    beq.s   .waithigh
.waitlow
    cmp.b   #(303&$FF),VPOSR+2		; wait until low byte = $2F
    bne.s   .waitlow
    rts
;
; void lwmf_ClearMemCPU(__reg("a1") long* StartAddress, __reg("d7") long NumberOfBytes);
;

_lwmf_ClearMemCPU::
	movem.l d2-d7/a2-a6,-(sp)       ; save all registers

	adda.l  d7,a1                   ; we go top -> down
	lsr.l   #2,d7                   ; divide by 4
	moveq   #0,d0                   ; d0=0 (before lsr so CC is set by lsr, not moveq)
	move.l  d7,d6
	lsr.l   #7,d6                   ; get number of blocks of 128 long words
	beq.s   .clear                  ; branch if we have no complete block
	subq.l  #1,d6                   ; adjust count for dbra
	; init zero registers via register-to-register moves
	move.l  d0,d1
	move.l  d0,d2
	move.l  d0,d3
	move.l  d0,d4
	move.l  d0,d5
	move.l  d0,a2
	move.l  d0,a3
	move.l  d0,a4
	move.l  d0,a5
	move.l  d0,a6
.clearblock
	movem.l d0-d5/a2-a6,-(a1)       ; 11 registers -> clear 44 bytes at once
	movem.l d0-d5/a2-a6,-(a1)
	movem.l d0-d5/a2-a6,-(a1)
	movem.l d0-d5/a2-a6,-(a1)
	movem.l d0-d5/a2-a6,-(a1)
	movem.l d0-d5/a2-a6,-(a1)
	movem.l d0-d5/a2-a6,-(a1)
	movem.l d0-d5/a2-a6,-(a1)
	movem.l d0-d5/a2-a6,-(a1)
	movem.l d0-d5/a2-a6,-(a1)
	movem.l d0-d5/a2-a6,-(a1)
	movem.l d0-d5/a2,-(a1)          ; 7 registers
	dbra    d6,.clearblock
.clear
	and.l   #$7F,d7                 ; remainder after 128-longword blocks (7 bits)
	beq.s   .done
	; d0 is always 0 (set unconditionally above)
.setword
	move.l  d0,-(a1)                ; clear memory by one long word at a time
	subq.l  #1,d7
	bne.s   .setword
.done
	movem.l (sp)+,d2-d7/a2-a6       ; restore registers
	rts

;
; void lwmf_ClearScreen(__reg("a0") long* StartAddress);
;

_lwmf_ClearScreen::
	movem.l d2-d7/a1-a6,-(sp)       						; save all registers
	lea		CUSTOMREGS,a1									; a1 = CUSTOMREGS base for compact addressing

	; Clear first half of screen with blitter
	bsr     _lwmf_WaitBlitter
	move.l  #$01000000,BLTCON0								; enable destination only (both BLTCON0 and BLTCON1 are written!)
	clr.w   (BLTDMOD-CUSTOMREGS,a1)							; modulo = 0 (contiguous)
	move.l  a0,(BLTDPTH-CUSTOMREGS,a1)
	move.w  #SCREENCLRSIZEBLT,(BLTSIZE-CUSTOMREGS,a1)

	; Clear rest of screen with cpu
	move.l  #SCREENCLRSIZECPU,d7
	adda.l  d7,a0	                  						; we go top -> down
	lsr.l   #3,d7                   						; divide by 8, we only need to clear half of the screen...
	moveq   #0,d0                   						; d0=0 (before lsr so CC is set by lsr, not moveq)
	move.l  d7,d6
	lsr.l   #7,d6                   						; get number of blocks of 128 long words
	beq.s   .clear                  						; branch if we have no complete block
	subq.l  #1,d6                   						; adjust count for dbra
	; init zero registers via register-to-register moves
	move.l  d0,d1
	move.l  d0,d2
	move.l  d0,d3
	move.l  d0,d4
	move.l  d0,d5
	move.l  d0,a2
	move.l  d0,a3
	move.l  d0,a4
	move.l  d0,a5
	move.l  d0,a6
.clearblock
	movem.l d0-d5/a2-a6,-(a0)       						; 11 registers -> clear 44 bytes at once
	movem.l d0-d5/a2-a6,-(a0)
	movem.l d0-d5/a2-a6,-(a0)
	movem.l d0-d5/a2-a6,-(a0)
	movem.l d0-d5/a2-a6,-(a0)
	movem.l d0-d5/a2-a6,-(a0)
	movem.l d0-d5/a2-a6,-(a0)
	movem.l d0-d5/a2-a6,-(a0)
	movem.l d0-d5/a2-a6,-(a0)
	movem.l d0-d5/a2-a6,-(a0)
	movem.l d0-d5/a2-a6,-(a0)
	movem.l d0-d5/a2,-(a0)          						; 7 registers
	dbra    d6,.clearblock
.clear
	and.l   #$7F,d7                 						; remainder after 128-longword blocks (7 bits)
	beq.s   .done

	; d0 is always 0 (set unconditionally above)
.setword
	move.l  d0,-(a0)                						; clear memory by one long word at a time
	subq.l  #1,d7
	bne.s   .setword
.done
	movem.l (sp)+,d2-d7/a1-a6       						; restore registers
	rts

;
; void lwmf_BlitClearLines(__reg("d0") WORD StartLine, __reg("d1") WORD NumberOfLines, __reg("a0") long* Target);
;

_lwmf_BlitClearLines::
    movem.l d2-d4/a1,-(sp)							; save registers
	lea		CUSTOMREGS,a1							; a1 = CUSTOMREGS base for compact addressing

    moveq   #BYTESPERROW,d2
    moveq   #NUMBEROFBITPLANES,d4
    mulu    d4,d2            						; d2 = BYTESPERROW * NUMBEROFBITPLANES

	move.l  d2,d4
    lsr.l   #1,d4									; (BYTESPERROW * NUMBEROFBITPLANES) >> 1

	move.l  d1,d3

    ; Calculate target adress
    mulu    d0,d2            						; d2 = startLine * BYTESPERROW * NUMBEROFBITPLANES
    add.l   a0,d2            						; d2 = Target address for blitter

	bsr     _lwmf_WaitBlitter

    ; Set Blitter register
	move.l  #$01000000,(BLTCON0-CUSTOMREGS,a1)		; enable destination only (both BLTCON0 and BLTCON1 are written!)
    clr.w	(BLTDMOD-CUSTOMREGS,a1)   				; modulo = 0 (contiguous)
    move.l  d2,(BLTDPTH-CUSTOMREGS,a1)     			; BLTDPTH = Targetadress

    ; Blit
    lsl.w   #6,d3
    or.w    d4,d3
    move.w  d3,(BLTSIZE-CUSTOMREGS,a1)

    movem.l (sp)+,d2-d4/a1							; restore registers
    rts

;
; void lwmf_SetPixel(__reg("d0") WORD PosX,
;                    __reg("d1") WORD PosY,
;                    __reg("d2") UBYTE Color,
;                    __reg("a0") UBYTE* Target);
;
; Optimized for contiguous planar layout:
; each scanline contains all bitplanes back-to-back
;

_lwmf_SetPixel::
    movem.l d2-d7/a1,-(sp)

    ; d7 = full scanline stride in bytes over all bitplanes
    moveq   #BYTESPERROW,d7
    moveq   #NUMBEROFBITPLANES,d6
    mulu    d6,d7                          ; d7 = BYTESPERROW * NUMBEROFBITPLANES

    ; a0 = start of scanline y
    mulu    d7,d1
    adda.l  d1,a0

    ; a0 = byte containing pixel x in plane 0 of this scanline
    move.w  d0,d5
    lsr.w   #3,d5                          ; x / 8
    adda.w  d5,a0

    ; d4 = bit mask = 1 << (7 - (x & 7))
    move.w  d0,d4
    and.w   #7,d4
    moveq   #7,d5
    sub.w   d4,d5                          ; d5 = 7 - (x & 7)
    moveq   #1,d4
    lsl.b   d5,d4                          ; d4.b = mask

    move.b  d4,d5
    not.b   d5                             ; d5.b = inverted mask

    moveq   #NUMBEROFBITPLANES-1,d6
.plane
    move.b  (a0),d3                        ; current destination byte
    lsr.b   #1,d2                          ; next color bit -> carry
    bcc.s   .clear
.set
    or.b    d4,d3
    bra.s   .store
.clear
    and.b   d5,d3
.store
    move.b  d3,(a0)
    lea     BYTESPERROW(a0),a0             ; next plane, same scanline
    dbra    d6,.plane

    movem.l (sp)+,d2-d7/a1
    rts

; ***************************************************************************************************
; * Variables                                                                                       *
; ***************************************************************************************************

;
; System take over
;

olddma:
	dc.w    0

oldintena:
	dc.w    0

oldintreq:
	dc.w    0

oldadkcon:
	dc.w    0

oldview:
	dc.l    0

oldcopper:
	dc.l    0

;
; Libraries
;

gfxlib:
	dc.b    "graphics.library",0

	even
_GfxBase::
	dc.l    0


