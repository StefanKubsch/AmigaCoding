; Various assembler functions for lwmf
; Code is compatible with Motorola syntax as provided by vbcc
; Optimized for 68020+ (Amiga 1200 and up)
;
; Coded in 2020-2026 by Stefan Kubsch / Deep4

	machine	68020

; ***************************************************************************************************
; * Global                                                                                          *
; ***************************************************************************************************

; Screen stuff
; Change it according to your needs!
;
; Export constants to "Define.h" for further use in C
; vasmm68k_mot -Fcdef -o ".\lwmf\Defines.h" ".\lwmf\lwmf_hardware_vasm.s"

SCREENWIDTH         equ     320
SCREENHEIGHT        equ     256
NUMBEROFBITPLANES   equ     3

BYTESPERROW			equ     SCREENWIDTH/8
SCREENWIDTHTOTAL	equ		BYTESPERROW*NUMBEROFBITPLANES
SCREENCLRSIZEBLT    equ     128*NUMBEROFBITPLANES*64+BYTESPERROW/2      ; half screen size for blitter part of screen clear (top -> mid)
SCREENCLRSIZECPU    equ     SCREENWIDTHTOTAL*SCREENHEIGHT			 	; size for cpu part of screen clear ( bottom -> mid)

; CUSTOMREGS registers

EXECBASE            equ     $4
CUSTOMREGS		    equ     $00DFF000		; Base address of CUSTOM registers

ADKCON              equ     $00DFF09E		; Audio/Disk control read/write
ADKCONR             equ     $00DFF010		; Audio/Disk control read
BLTCON0 	        equ     $00DFF040		; Blitter control reg 0
BLTCON1 	        equ     $00DFF042		; Blitter control reg 1
BLTAFWM             equ     $00DFF044		; Blitter first word mask for source A
BLTALWM             equ     $00DFF046		; Blitter last word mask for source A
BLTAPTH             equ     $00DFF050		; Blitter pointer to destination A (high 5 bits)
BLTSIZE 	        equ     $00DFF058		; Blitter start and size (win/width, height)
BLTSIZH				equ		$00DFF05E		; Blitter H size and start (for 11 bit H size)
BLTSIZV				equ		$00DFF05C		; Blitter vertical size (15 bit height)
BLTAMOD             equ     $00DFF064		; Blitter modulo for A
BLTDMOD 	        equ     $00DFF066		; Blitter modulo for D
BLTDPTH		        equ     $00DFF054		; Blitter pointer to destination D (high 5 bits)
COP1LCH             equ     $00DFF080		; Coprocessor first location register (high 5 bits)
DMACON              equ     $00DFF096		; DMA control (and blitter status) read/write
DMACONR             equ     $00DFF002		; DMA control (and blitter status) read
INTENA              equ     $00DFF09A		; Interrupt enable read/write
INTENAR             equ     $00DFF01C		; Interrupt enable read
INTREQ              equ     $00DFF09C		; Interrupt request read/write
INTREQR             equ     $00DFF01E		; Interrupr request read
VPOSR               equ     $00DFF004		; Read vert most sig. bits (and frame flop)

DMAB_BLITTER        equ		6				; DMACONR bit 14 - blitter busy flag

; Library vector offsets (LVO)

; graphics.library
LVOLoadView         equ     -222
LVOWaitTOF          equ     -270
LVOOwnBlitter		equ		-456
LVODisownBlitter	equ		-462

; exec.library
LVOForbid           equ     -132
LVOPermit           equ     -138
LVOFindTask         equ     -294
LVOSetTaskPri       equ     -300
LVOOpenLibrary      equ     -552
LVOCloseLibrary     equ     -414

; Constants

MINVERSION          equ     39        ; set required version (39 -> Amiga OS 3.0 and higher)
GFX_ACTIVIEW        equ     34        ; GfxBase offset: pointer to active View
GFX_COPINIT         equ     38        ; GfxBase offset: system copper list pointer
DMASET_DEMO         equ     $83C0     ; SET | DMAEN | BPLEN | COPEN | BLTEN (no sprites)

; Magic constants

WORD_ALIGN_MASK      EQU $FFF0
BLTCON0_COPY_A_TO_D  EQU $09F0


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
; * Library handling                                                       *
; **************************************************************************

;
; UWORD lwmf_LoadGraphicsLib(void);
;

_lwmf_LoadGraphicsLib::
	move.l	a6,-(sp)                ; save register on stack
	move.l	EXECBASE.w,a6           ; use exec base address

	lea     gfxlib(pc),a1
	moveq   #MINVERSION,d0
	jsr     LVOOpenLibrary(a6)
	move.l  d0,_GfxBase             ; store adress of GfxBase in variable
	bne.s   .success

	moveq   #20,d0                  ; return with error
	bra.s	.exit
.success
	moveq	#0,d0					; return with success
.exit
	movea.l (sp)+,a6                ; restore register
	rts

;
; UWORD lwmf_LoadDatatypesLib(void);
;

_lwmf_LoadDatatypesLib::
	move.l	a6,-(sp)                ; save register on stack
	move.l	EXECBASE.w,a6           ; use exec base address

	lea     datatypeslib(pc),a1
	moveq   #MINVERSION,d0
	jsr     LVOOpenLibrary(a6)
	move.l  d0,_DataTypesBase 		; store adress of DataTypeBase in variable
	bne.s   .success

	moveq   #20,d0                  ; return with error
	bra.s	.exit
.success
	moveq	#0,d0					; return with success
.exit
	movea.l (sp)+,a6                ; restore register
	rts

;
; void lwmf_CloseLibraries(void);
;

_lwmf_CloseLibraries::
	move.l  EXECBASE.w,a6           ; use exec base address

	move.l  _DataTypesBase(pc),d0
	beq.s   .checkgfx               ; skip if not open
	move.l  d0,a1
	jsr     LVOCloseLibrary(a6)
	clr.l   _DataTypesBase
.checkgfx
	move.l  _GfxBase(pc),d0
	beq.s   .done                   ; skip if not open
	move.l  d0,a1
	jsr     LVOCloseLibrary(a6)
	clr.l   _GfxBase
.done
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

	move.w  #$7FFF,DMACON       		; clear all DMA channels
	move.w  #DMASET_DEMO,DMACON 		; re-enable bitplane/copper/blitter DMA

	move.l	EXECBASE.w,a6
	suba.l  a1,a1                   	; zero a1 (NULL = current task for FindTask)
	jsr     LVOFindTask(a6)         	; find current task
	move.l  d0,a1
	moveq   #20,d0                  	; set task priority (20 should be enough!)
	jsr     LVOSetTaskPri(a6)

	jsr     LVOForbid(a6)

	movea.l (sp)+,a6                	; restore register
	rts

;
; void lwmf_ReleaseOS(void);
;

_lwmf_ReleaseOS::
	move.l	a6,-(sp)                    ; save register on stack

	bsr     _lwmf_WaitBlitter           ; wait for any in-progress blit before restoring DMA

	move.w  #$7FFF,DMACON
	move.w  olddma(pc),DMACON
	move.w  #$7FFF,INTREQ               ; clear all pending interrupts before re-enabling (write twice - hardware quirk)
	move.w  #$7FFF,INTREQ
	move.w  oldintreq(pc),INTREQ
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

	movea.l (sp)+,a6                    ; restore register
   	rts

; **************************************************************************
; * System functions                                                       *
; **************************************************************************

;
; void lwmf_OwnBlitter(void);
;

_lwmf_OwnBlitter::
	move.l	a6,-(sp)                ; save register on stack
	move.l  _GfxBase(pc),a6
	jsr     LVOOwnBlitter(a6)
	movea.l (sp)+,a6                ; restore register
   	rts

;
; void lwmf_DisownBlitter(void);
;

_lwmf_DisownBlitter::
	move.l	a6,-(sp)                ; save register on stack
	move.l  _GfxBase(pc),a6
	jsr     LVODisownBlitter(a6)
	movea.l (sp)+,a6                ; restore register
   	rts

;
; void lwmf_WaitBlitter(void);
;

_lwmf_WaitBlitter::
	btst.b  #DMAB_BLITTER,DMACONR       ; already idle? skip nasty mode entirely
	beq.s   .done
	move.w	#$8400,DMACON				; enable blitter nasty
.loop
	btst.b 	#DMAB_BLITTER,DMACONR 		; check blitter busy flag
	bne.s 	.loop
	move.w	#$0400,DMACON				; disable blitter nasty
.done
	rts

;
; void lwmf_WaitVertBlank(void);
;

_lwmf_WaitVertBlank::
	; Line 303 = $12F: V8=1 (bit 0 of VPOSR+1), V7:V0=$2F (byte at VPOSR+2)
	; Two-phase check uses byte reads for lower chip bus pressure
.waithigh
	btst.b	#0,VPOSR+1			; test V8 - are we on lines 256+?
	beq.s	.waithigh 			; no, keep waiting
.waitlow
	move.b	VPOSR+2,d0			; read V7:V0
	cmp.b	#(303&$FF),d0		; = $2F
	bne.s	.waitlow
	rts

;
; void lwmf_ClearMemCPU(__reg("a1") long* StartAddress, __reg("d7") long NumberOfBytes);
;

_lwmf_ClearMemCPU::
	movem.l d2-d6/a2-a6,-(sp)       ; save all registers

	adda.l  d7,a1                   ; we go top -> down
	lsr.l   #2,d7                   ; divide by 4
	moveq   #0,d0                   ; d0=0 (before lsr so CC is set by lsr, not moveq)
	move.l  d7,d6
	lsr.l   #7,d6                   ; get number of blocks of 128 long words
	beq.s   .clear                  ; branch if we have no complete block
	; 68020: init zero regs via register-to-register moves (no zeros data table reads)
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
	subq.l  #1,d6                   ; 68020+: subq.l/bne replaces dbra (faster, 32-bit counter)
	bne.s   .clearblock
.clear
	and.l   #$7F,d7                 ; remainder after 128-longword blocks (7 bits)
	beq.s   .done
	; d0 is always 0 (set unconditionally above)
.setword
	move.l  d0,-(a1)                ; clear memory by one long word at a time
	subq.l  #1,d7
	bne.s   .setword
.done
	movem.l (sp)+,d2-d6/a2-a6       ; restore registers
	rts

;
; void lwmf_ClearScreen(__reg("a1") long* StartAddress);
;

_lwmf_ClearScreen::
	movem.l d2-d7/a2-a6,-(sp)       	; save all registers

	; Clear first half of screen with blitter
	bsr     _lwmf_WaitBlitter
	move.l  #$01000000,BLTCON0			; enable destination only (both BLTCON0 and BLTCON1 are written!)
	clr.w   BLTDMOD						; modulo = 0 (contiguous)
	move.l  a1,BLTDPTH
	move.w  #SCREENCLRSIZEBLT,BLTSIZE

	; Clear rest of screen with cpu
	move.l  #SCREENCLRSIZECPU,d7
	adda.l  d7,a1                   	; we go top -> down
	lsr.l   #3,d7                   	; divide by 8, we only need to clear half of the screen...
	moveq   #0,d0                   	; d0=0 (before lsr so CC is set by lsr, not moveq)
	move.l  d7,d6
	lsr.l   #7,d6                   	; get number of blocks of 128 long words
	beq.s   .clear                  	; branch if we have no complete block
	; 68020: init zero regs via register-to-register moves (no zeros data table reads)
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
	movem.l d0-d5/a2-a6,-(a1)       	; 11 registers -> clear 44 bytes at once
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
	movem.l d0-d5/a2,-(a1)          	; 7 registers
	subq.l  #1,d6                   	; 68020+: subq.l/bne replaces dbra (faster, 32-bit counter)
	bne.s   .clearblock
.clear
	and.l   #$7F,d7                 	; remainder after 128-longword blocks (7 bits)
	beq.s   .done

	; d0 is always 0 (set unconditionally above)
.setword
	move.l  d0,-(a1)                	; clear memory by one long word at a time
	subq.l  #1,d7
	bne.s   .setword
.done
	movem.l (sp)+,d2-d7/a2-a6       	; restore registers
	rts

;
; void lwmf_BlitClearLines(__reg("d0") WORD StartLine, __reg("d1") WORD NumberOfLines, __reg("a0") long* Target);
;

_lwmf_BlitClearLines::
    movem.l d2-d4/a1,-(sp)			; save registers

    moveq   #BYTESPERROW,d2
    moveq   #NUMBEROFBITPLANES,d4
    mulu    d4,d2            		; d2 = BYTESPERROW * NUMBEROFBITPLANES

	move.l  d2,d4
    lsr.l   #1,d4					; (BYTESPERROW * NUMBEROFBITPLANES) >> 1

	move.l  d1,d3

    ; Calculate target adress
    mulu    d0,d2            		; d2 = startLine * BYTESPERROW * NUMBEROFBITPLANES
    add.l   a0,d2            		; d2 = Target address for blitter

	bsr     _lwmf_WaitBlitter

    ; Set Blitter register
	move.l  #$01000000,BLTCON0		; enable destination only (both BLTCON0 and BLTCON1 are written!)
    clr.w	BLTDMOD   				; modulo = 0 (contiguous)
    move.l  d2,BLTDPTH     			; BLTDPTH = Targetadress

    ; Blit
    lsl.w   #6,d3
    or.w    d4,d3
    move.w  d3,BLTSIZE

    movem.l (sp)+,d2-d4/a1			; restore registers
    rts

;
; void lwmf_SetPixel(__reg("d0") WORD PosX, __reg("d1") WORD PosY,  __reg("d2") UBYTE Color,  __reg("a0") long* Target);
;

_lwmf_SetPixel::
    movem.l d2-d4,-(sp)				; save registers

    muls.w  #SCREENWIDTHTOTAL,d1    ; PosY * stride
    move.w  d0,d3
    not.w   d3                      ; low 3 bits = 7-(x&7)
    lsr.w   #3,d0                   ; byte offset instead of ASR
    adda.l  d1,a0                   ; Move the destination address forward once
    adda.w  d0,a0

    moveq   #NUMBEROFBITPLANES-1,d4
.loop
    lsr.b   #1,d2                   ; Plane-Bit -> Carry
    bcc.s   .skip
    bset    d3,(a0)
.skip
    lea     BYTESPERROW(a0),a0      ; next Bitplane
    dbra    d4,.loop

    movem.l (sp)+,d2-d4				; restore registers
    rts

; void lwmf_BlitTile(__reg("a0") long* SrcAddr, __reg("d0") WORD SrcX, __reg("d1") WORD SrcY, __reg("a1") long* DstAddr, __reg("d2") WORD DstX, __reg("d3") WORD DstY, __reg("d4") WORD Width, __reg("d5") WORD Height, __reg("d6") WORD SrcWidth);
;
; All coordinates (SrcX, SrcY, DstX, DstY) and dimensions (Width, Height) are in pixels -> works currently only fine for multiples of 16 pixels (word-aligned) due to the way masks are calculated. Non-word-aligned blits will require additional masking and shifting logic.
; Source bitmap is interleaved with NUMBEROFBITPLANES planes; destination uses SCREENWIDTHTOTAL row stride.
;

_lwmf_BlitTile::
	movem.l	d2-d7/a2-a3,-(sp)					; save registers
	lea		CUSTOMREGS,a2							; a2 = CUSTOMREGS base for compact addressing

	; --------------------------------------------------
	; 1) src_bprow = SrcWidth / 8 (single bitplane row)
	;    src_row_bytes = src_bprow * NUMBEROFBITPLANES (interleaved)
	;    68020: keep src_bprow in d7 for modulo calc later,
	;    compute interleaved stride with lsl+add (replaces mulu)
	; --------------------------------------------------
	move.w	d6,d7								; d7 = SrcWidth (pixels)
	lsr.w	#3,d7								; d7 = SrcWidth/8 = src_bprow (bytes per bitplane row)
	move.w	d7,d6								; d6 = src_bprow (preserve for modulo calc in step 9)
	; 68020+: x*3 = x + (x<<1) — replaces mulu.w #NUMBEROFBITPLANES
	add.w	d7,d7								; d7 = src_bprow * 2
	add.w	d6,d7								; d7 = src_bprow * 3 = src_row_bytes (interleaved)

	; --------------------------------------------------
	; 2) Source pointer: a0 += SrcY * src_row_bytes + (SrcX & ~15) / 8
	;    68020: use 32-bit scale-factor addressing where beneficial
	; --------------------------------------------------
	move.w	d0,a3								; a3 = SrcX (preserve for later)
	; 68020+: mulu.w result is 32-bit already, no ext needed
	mulu.w	d7,d1								; d1 = SrcY * src_row_bytes
	adda.l	d1,a0								; a0 += row offset
	move.w	d0,d1
	andi.w	#WORD_ALIGN_MASK,d1					; align SrcX down to word boundary
	lsr.w	#3,d1								; byte offset of that word
	; 68020+: add.w with address register auto-extends to 32-bit
	adda.w	d1,a0								; a0 = source pointer (word-aligned)

	; --------------------------------------------------
	; 3) Dest pointer: a1 += DstY * SCREENWIDTHTOTAL + (DstX & ~15) / 8
	; --------------------------------------------------
	mulu.w	#SCREENWIDTHTOTAL,d3				; d3 = DstY * SCREENWIDTHTOTAL
	adda.l	d3,a1								; a1 += row offset
	move.w	d2,d3
	andi.w	#WORD_ALIGN_MASK,d3					; align DstX down to word boundary
	lsr.w	#3,d3								; byte offset
	; 68020+: add.w with address register auto-extends to 32-bit
	adda.w	d3,a1								; a1 = dest pointer (word-aligned)

	; --------------------------------------------------
	; 4) Barrel shift = ((DstX & 15) - (SrcX & 15)) & 15
	; --------------------------------------------------
	move.w	a3,d3								; d3 = SrcX
	andi.w	#$F,d3								; d3 = srcStartBit
	move.w	d2,d1								; d1 = DstX
	andi.w	#$F,d1								; d1 = dstStartBit
	sub.w	d3,d1								; d1 = dstStartBit - srcStartBit (signed)
	andi.w	#$F,d1								; d1 = barrel shift (0..15)

	; --------------------------------------------------
	; 5) Blit width in words
	;    srcWidthWords  = (srcStartBit + Width + 15) >> 4
	;    blitWidthWords = srcWidthWords + (shift ? 1 : 0)
	; --------------------------------------------------
	move.w	d3,d0								; d0 = srcStartBit
	add.w	d4,d0								; d0 = srcStartBit + Width
	move.w	d0,d2								; d2 = srcStartBit + Width (save for last mask)
	add.w	#15,d0
	lsr.w	#4,d0								; d0 = srcWidthWords

	tst.w	d1
	beq.s	.noExtra
	addq.w	#1,d0								; extra word for shifted output
.noExtra:
	move.w	d0,a3								; a3 = blitWidthWords (save)

	; --------------------------------------------------
	; 6) First word mask: BLTAFWM = $FFFF >> srcStartBit
	;    Masks are applied to source A BEFORE the barrel
	;    shift, so they must be in source coordinates.
	; --------------------------------------------------
	moveq	#-1,d0								; d0 = $FFFF
	lsr.w	d3,d0								; d0 = first word mask

	; --------------------------------------------------
	; 7) Last word mask (source space)
	;    srcEndBit = (srcStartBit + Width - 1) & 15
	;    BLTALWM  = $FFFF << (15 - srcEndBit)
	;
	;    When shift != 0 an extra word is appended. That
	;    extra word has no source data, so BLTALWM = $0000
	;    to prevent stale A-channel data from leaking in.
	; --------------------------------------------------
	tst.w	d1									; shift == 0?
	beq.s	.calcLWM
	moveq	#0,d3								; extra word -> block all source bits
	bra.s	.masksReady
.calcLWM:
	move.w	d2,d3								; d3 = srcStartBit + Width
	subq.w	#1,d3
	andi.w	#$F,d3								; d3 = srcEndBit (0..15)
	moveq	#15,d4
	sub.w	d3,d4								; d4 = 15 - srcEndBit
	moveq	#-1,d3								; d3 = $FFFF
	lsl.w	d4,d3								; d3 = last word mask
.masksReady:

	; d0 = BLTAFWM, d3 = BLTALWM, d1 = barrel shift

	; --------------------------------------------------
	; 8) BLTCON0 = (shift << 12) | $09F0  (USE A+D, LF = D=A)
	;    68020+: use lsl.w #8 + lsl.w #4 decomposition
	;    (avoids ror.w pipeline stall on 68020)
	; --------------------------------------------------
	move.w	d1,d4								; d4 = shift (0..15)
	lsl.w	#8,d4								; shift into bits 11..8
	lsl.w	#4,d4								; shift into bits 15..12
	ori.w	#BLTCON0_COPY_A_TO_D,d4				; d4 = BLTCON0

	; --------------------------------------------------
	; 9) Modulos = single-plane row width - (blitWidthWords * 2)
	;    68020+: d6 still holds src_bprow from step 1
	;    (eliminates the expensive divu.w #NUMBEROFBITPLANES)
	; --------------------------------------------------
	move.w	a3,d1								; d1 = blitWidthWords
	add.w	d1,d1								; d1 = blitWidthBytes
	move.w	d6,d2								; d2 = src_bprow (single-plane row width from step 1)
	sub.w	d1,d2								; d2 = SrcModulo (per bitplane row)
	move.w	#BYTESPERROW,d7
	sub.w	d1,d7								; d7 = DstModulo (per bitplane row)

	; --------------------------------------------------
	; 10) Program blitter and start
	; --------------------------------------------------
	bsr		_lwmf_WaitBlitter

	move.l	a0,(BLTAPTH-CUSTOMREGS,a2)				; source A pointer
	move.l	a1,(BLTDPTH-CUSTOMREGS,a2)				; destination D pointer

	; BLTCON0 + BLTCON1 in one longword write
	swap	d4									; d4 = [BLTCON0 | old]
	clr.w	d4									; d4 = [BLTCON0 | 0000] (BLTCON1 = 0)
	move.l	d4,(BLTCON0-CUSTOMREGS,a2)

	; BLTAFWM + BLTALWM in one longword write
	swap	d0									; d0 = [FWM | old]
	move.w	d3,d0								; d0 = [FWM | LWM]
	move.l	d0,(BLTAFWM-CUSTOMREGS,a2)

	; BLTAMOD + BLTDMOD in one longword write
	swap	d2									; d2 = [SrcMod | old]
	move.w	d7,d2								; d2 = [SrcMod | DstMod]
	move.l	d2,(BLTAMOD-CUSTOMREGS,a2)

	; BLTSIZV + BLTSIZH in one longword write (BLTSIZH write triggers blit)
	; Height must be multiplied by NUMBEROFBITPLANES for interleaved bitmaps:
	; each pixel row spans NUMBEROFBITPLANES consecutive bitplane rows in memory.
	; 68020+: x*3 = x + (x<<1) — replaces mulu.w #NUMBEROFBITPLANES
	move.w	d5,d0								; d0 = Height
	add.w	d5,d5								; d5 = Height * 2
	add.w	d0,d5								; d5 = Height * 3 = total blitter rows
	swap	d5									; d5 = [blitHeight | old]
	move.w	a3,d5								; d5 = [blitHeight | blitWidthWords]
	move.l	d5,(BLTSIZV-CUSTOMREGS,a2)				; start blit!

	movem.l	(sp)+,d2-d7/a2-a3					; restore registers
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

datatypeslib:
	dc.b    "datatypes.library",0

	even
_DataTypesBase::
	dc.l    0
