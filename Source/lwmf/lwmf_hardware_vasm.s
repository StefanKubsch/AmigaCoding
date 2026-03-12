; Various assembler functions for lwmf
; Code is compatible with Motorola syntax as provided by vbcc
;
; Coded in 2020-2021 by Stefan Kubsch / Deep4

; ***************************************************************************************************
; * Global                                                                                          *
; ***************************************************************************************************

; Screen stuff
; Change it according to your needs!

SCREENWIDTH         equ     320
SCREENHEIGHT        equ     256
NUMBITPLANES        equ     3

SCREENBROW			equ     SCREENWIDTH/8
SCREENWIDTHTOTAL	equ		SCREENBROW*NUMBITPLANES
SCREENCLRSIZEBLT    equ     128*NUMBITPLANES*64+SCREENBROW/2        ; half screen size for blitter part of screen clear (top -> mid)
SCREENCLRSIZECPU    equ     SCREENWIDTHTOTAL*SCREENHEIGHT			; size for cpu part of screen clear ( bottom -> mid)

; Custom registers

EXECBASE            equ     $4
CUSTOM		        equ     $00DFF000		; Base address of custom registers

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
DMASET_DEMO         equ     $83C0     ; SET | DMAEN | BPLEN | COPEN | BLTEN (no sprites)
GFX_ACTIVIEW        equ     34        ; GfxBase offset: pointer to active View
GFX_COPINIT         equ     38        ; GfxBase offset: system copper list pointer

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
	move.l	a6,-(sp)                ; save register on stack

	move.w  DMACONR,d0          	; store current custom registers for later restore
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
	move.l  GFX_COPINIT(a6),oldcopper  ; store current copperlist
	suba.l  a1,a1                   ; Set a1 to zero
	jsr     LVOLoadView(a6)	        ; LoadView(NULL)
	jsr     LVOWaitTOF(a6)
	jsr     LVOWaitTOF(a6)

	bsr     _lwmf_WaitBlitter        ; wait for any in-progress blit before killing DMA

	move.w  #$7FFF,DMACON       	; clear all DMA channels
	move.w  #DMASET_DEMO,DMACON 	; re-enable bitplane/copper/blitter DMA

	move.l	EXECBASE.w,a6
	suba.l  a1,a1                   ; zero a1 (NULL = current task for FindTask)
	jsr     LVOFindTask(a6)         ; find current task
	move.l  d0,a1
	moveq   #20,d0                  ; set task priority (20 should be enough!)
	jsr     LVOSetTaskPri(a6)

	jsr     LVOForbid(a6)

	movea.l (sp)+,a6                ; restore register
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
.waithi
	btst.b	#0,VPOSR+1			; test V8 - are we on lines 256+?
	beq.s	.waithi				; no, keep waiting
.waitlo
	move.b	VPOSR+2,d0			; read V7:V0
	cmp.b	#(303&$FF),d0		; = $2F
	bne.s	.waitlo
	rts

;
; void lwmf_ClearMemCPU(__reg("a1") long* StartAddress, __reg("d7") long NumberOfBytes);
;

_lwmf_ClearMemCPU::
	movem.l d2-d6/a2-a6,-(sp)       ; save all registers

	lea     zeros(pc),a0
	add.l   d7,a1                   ; we go top -> down
	lsr.l   #2,d7                   ; divide by 4
	move.l  d7,d6
	lsr.l   #7,d6                   ; get number of blocks of 128 long words 
	beq.s   .clear                  ; branch if we have no complete block
	subq.l  #1,d6                   ; one less to get loop working
	movem.l (a0),d0-d5/a2-a6        ; clear all registers
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
	moveq   #0,d0                   ; ensure d0 = 0 if no complete blocks were processed
	and.l   #$7F,d7                 ; remainder after 128-longword blocks (7 bits)
	beq.s   .done
	subq.l  #1,d7                   ; one less to get loop working
.setword
	move.l  d0,-(a1)                ; clear memory by one long word at a time
	dbra    d7,.setword
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
	lea     zeros(pc),a0
	move.l  #SCREENCLRSIZECPU,d7
	add.l   d7,a1                   	; we go top -> down
	lsr.l   #3,d7                   	; divide by 8, we only need to clear half of the screen...
	move.l  d7,d6
	lsr.l   #7,d6                   	; get number of blocks of 128 long words
	beq.s   .clear                  	; branch if we have no complete block
	subq.l  #1,d6                   	; one less to get loop working
	movem.l (a0),d0-d5/a2-a6			; zero d0-d5/a2-a6 for bulk write
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
	dbra    d6,.clearblock
.clear
	and.l   #$7F,d7                 	; remainder after 128-longword blocks (7 bits)
	beq.s   .done
	subq.l  #1,d7                   	; one less to get loop working

	; d0 is already 0 from the movem.l above; a1 is still the write pointer
.setword
	move.l  d0,-(a1)                	; clear memory by one long word at a time
	dbra    d7,.setword
.done
	movem.l (sp)+,d2-d7/a2-a6       	; restore registers
	rts

;
; void lwmf_SetPixel(__reg("d0") WORD PosX, __reg("d1") WORD PosY,  __reg("d2") UBYTE Color,  __reg("a0") long* Target);
;

_lwmf_SetPixel::
	move.l  d3,-(sp)                            ; save d3 only

	muls.w  #SCREENWIDTHTOTAL,d1               ; address offset for line
	move.w  d0,d3                               ; calc x position
	not.w   d3                                  ; bit index within byte (MSB = leftmost pixel)
	asr.w   #3,d0                               ; byte offset for x position
	ext.l   d0                                  ; zero-extend to longword (upper word may be garbage from caller)
	add.l   d0,d1                               ; total byte offset

	; Bitplane 0 (Color bit 0) - NOTE: update all three planes if NUMBITPLANES changes
	ror.b   d2
	bpl.s   .skip0
	bset    d3,(a0,d1.l)
.skip0
	; Bitplane 1 (Color bit 1)
	lea     SCREENBROW(a0),a0
	ror.b   d2
	bpl.s   .skip1
	bset    d3,(a0,d1.l)
.skip1
	; Bitplane 2 (Color bit 2)
	lea     SCREENBROW(a0),a0
	ror.b   d2
	bpl.s   .skip2
	bset    d3,(a0,d1.l)
.skip2
	move.l  (sp)+,d3                            ; restore d3
	rts

;
; void lwmf_BlitTile(__reg("a0") long* SrcAddr, __reg("d0") WORD SrcModulo, __reg("d1") long SrcOffset, __reg("a1") long* DstAddr, __reg("d2") WORD PosX, __reg("d3") WORD PosY, __reg("d4") WORD Width, __reg("d5") WORD Height);
;

_lwmf_BlitTile::
	movem.l	d6-d7,-(sp)							; save registers

	; Source modulo
	subq.w	#2,d0								; subtract two more words from Source modulo because of barrel shift

	; Destination modulo (fold constant -2 into the immediate to eliminate subq)
	move.w	#SCREENWIDTHTOTAL-2,d7				; pre-subtract barrel-shift extra words
	sub.w	d4,d7							; subtract width in words
	sub.w	d4,d7							; subtract width in words

	; Calc screen position
	move.w	d2,d6							; store PosX for further use
	asr.w	#3,d6							; byte offset for PosX
	ext.l	d6								; zero-extend to longword (upper word may be garbage)
	mulu.w	#SCREENWIDTHTOTAL,d3				; multiply PosY with target width
	add.l	d6,a1							; add PosX byte offset to DstAddr
	add.l	d3,a1							; add PosY offset to DstAddr

	; Barrel shift
	andi.w	#$F,d2        						; clear all but lower nibble of PosX
	ror.w	#4,d2								; rotate right by four bits
	add.w	#$09F0,d2     						; D = A ($F0), ascending mode

	; Source offset
	add.l   d1,a0                   			; add source offset (in bytes) to SrcAddr

	; Add one word to Width because of barrel shift
	addq.w	#1,d4

	; ...and BLIT!
	bsr     _lwmf_WaitBlitter

	move.l  a0,BLTAPTH							; SrcAddr -> Blitter Source A
	move.l  a1,BLTDPTH							; DstAddr -> Blitter Destination D
	move.w  d2,BLTCON0
	clr.w   BLTCON1								; clear BLTCON1
	move.l	#$FFFF0000,BLTAFWM					; mask out first word (both BLTAFWM and BLTALWM are written!)
	move.w  d0,BLTAMOD							; modulo for Blitter Source A
	move.w  d7,BLTDMOD							; modulo for Blitter Destination D
	move.w	d5,BLTSIZV							; vertical blit size (Height)
	move.w	d4,BLTSIZH							; horizontal blit size (Width) - starts blit

	movem.l	(sp)+,d6-d7							; restore registers
	rts

; ***************************************************************************************************
; * Variables                                                                                       *
; ***************************************************************************************************

;
; Clear
;

zeros:
	dc.l    0,0,0,0,0,0,0,0,0,0,0

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