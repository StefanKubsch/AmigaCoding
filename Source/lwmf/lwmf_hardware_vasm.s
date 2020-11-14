; Various assembler functions for lwmf
; Code is compatible with Motorola syntax as provided by vbcc
;
; Coded in 2020 by Stefan Kubsch

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
BLTAFWM             equ     $00DFF044		; Blitter first-word mask for source A
BLTALWM             equ     $00DFF046		; Blitter last-word mask for source A
BLTAPTH             equ     $00DFF050		; Blitter pointer to destination A (high 5 bits)
BLTAPTL             equ     $00DFF052		; Blitter pointer to destination A (low 15 bits)
BLTDPTH		        equ     $00DFF054		; Blitter pointer to destination D (high 5 bits)
BLTDPTL             equ     $00DFF056		; Blitter pointer to destination D (low 15 bits)
BLTSIZE 	        equ     $00DFF058		; Blitter start and size (win/width, height)
BLTAMOD             equ     $00DFF064		; Blitter modulo for destination A
BLTDMOD 	        equ     $00DFF066		; Blitter modulo for destination D
BLTADAT             equ     $00DFF074		; Blitter source A data register
COP1LCH             equ     $00DFF080		; Coprocessor first location register (high 5 bits)
COP1LCL             equ     $00DFF082		; Coprocessor first location register (low 15 bits)
DMACON              equ     $00DFF096		; DMA control (and blitter status) read/write
DMACONR             equ     $00DFF002		; DMA control (and blitter status) read
INTENA              equ     $00DFF09A		; Interrupt enable read/write
INTENAR             equ     $00DFF01C		; Interrupt enable read
INTREQ              equ     $00DFF09C		; Interrupt request read/write
INTREQR             equ     $00DFF01E		; Interrupr request read
VPOSR               equ     $00DFF004		; Read vert most sig. bits (and frame flop)

DMAB_BLTDONE        equ		6				; DMACONR bit 14 - blitter busy flag

; Library vector offsets (LVO)

; graphics.library
LVOLoadView         equ     -222
LVOWaitTOF          equ     -270
; exec.library
LVOForbid           equ     -132
LVOPermit           equ     -138
LVOFindTask         equ     -294
LVOSetTaskPri       equ     -300
LVOOpenLibrary      equ     -552
LVOCloseLibrary     equ     -414

; Constants

MINVERSION          equ     39        ; set required version (39 -> Amiga OS 3.0 and higher)

; ***************************************************************************************************
; * Functions                                                                                       *
; ***************************************************************************************************

; Some words about registers
;
; a0,a1,d0,d1 are "scratch" registers - you can do what you want with 'em
; All other registers need to be saved before used in a function, and must be restored before returning
; Libraries expect their respective base address in a6

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
; __reg("d0") ULONG lwmf_LoadLibraries(void);
;

_lwmf_LoadLibraries::
	movem.l a6,-(sp)                ; save register on stack

	move.l	EXECBASE.w,a6           ; use exec base address
	
	lea     gfxlib(pc),a1           ; load graphics.library
	moveq   #MINVERSION,d0
	jsr     LVOOpenLibrary(a6)      
	tst.l   d0                      ; check if loading was successful
	beq.s   .open_failed            ; if d0 == 0 then failed
	move.l  d0,_GfxBase             ; store adress of GfxBase in variable
	
	lea     intuitionlib(pc),a1     ; load intuition.library
	moveq   #MINVERSION,d0
	jsr     LVOOpenLibrary(a6)      
	tst.l   d0                      
	beq.s   .open_failed
	move.l  d0,_IntuitionBase       

	lea     datatypeslib(pc),a1     ; load datatypes.library
	moveq   #MINVERSION,d0
	jsr     LVOOpenLibrary(a6)      
	tst.l   d0                     
	beq.s   .open_failed
	move.l  d0,_DataTypesBase       

	moveq   #0,d0                   ; return with success
	movea.l (sp)+,a6                ; restore registers
	rts
.open_failed
	bsr.b   _lwmf_CloseLibraries
	moveq   #20,d0                  ; return with error
	movea.l (sp)+,a6                ; restore register
	rts

;
; void lwmf_CloseLibraries(void);
;

_lwmf_CloseLibraries::
	move.l  EXECBASE.w,a6           ; use exec base address
	move.l  _DataTypesBase(pc),d0   ; use _DataTypesBase address in a1 for CloseLibrary     
	tst.l   d0
	bne.s   .closedatatypelib

	move.l  _IntuitionBase(pc),d0   ; use _IntuitionBase address in a1 for CloseLibrary      
	tst.l   d0  
	bne.s   .closeintuitionlib

	move.l  _GfxBase(pc),d0         ; use _GfxBase address in a1 for CloseLibrary                         
	tst.l   d0
	bne.s   .closegraphicslib
	rts
.closedatatypelib
	move.l  d0,a1                           
	jsr     LVOCloseLibrary(a6) 
	move.l  #0,_DataTypesBase
	rts
.closeintuitionlib
	move.l  d0,a1                           
	jsr     LVOCloseLibrary(a6)    
	move.l  #0,_IntuitionBase
	rts
.closegraphicslib
	move.l  d0,a1                           
	jsr     LVOCloseLibrary(a6)    
	move.l  #0,_GfxBase
	rts

; **************************************************************************
; * System take over                                                       *
; **************************************************************************

;
; void lwmf_TakeOverOS(void);
;

_lwmf_TakeOverOS::
	movem.l a6,-(sp)                ; save register on stack

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
	move.l  34(a6),oldview          ; store current view
	move.l  38(a6),oldcopper        ; store current copperlist
	suba.l  a1,a1                   ; Set a1 to zero
	jsr     LVOLoadView(a6)	        ; LoadView(NULL)
	jsr     LVOWaitTOF(a6)
	jsr     LVOWaitTOF(a6)

	bsr     _lwmf_WaitVertBlank
	move.w  #$7FFF,DMACON       	; clear DMACON / Description: http://amiga-dev.wikidot.com/hardware:dmaconr
	move.w  #$83C0,DMACON       	; set DMACON to 1000001111000000 = $83C0

	move.l	EXECBASE.w,a6
	sub.l   a1,a1                   ; find current task
	jsr     LVOFindTask(a6)
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
	movem.l a6,-(sp)                    ; save register on stack

	move.w  #$7FFF,DMACON
	move.w  olddma(pc),DMACON
	move.w  #$7FFF,INTENA
	move.w  oldintena(pc),INTENA
	move.w  #$7FFF,INTREQ
	move.w  oldintreq(pc),INTREQ
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
; void _lwmf_WaitBlitter(void)
;

_lwmf_WaitBlitter::
	move.w	#$8400,DMACON				; enable "blitter nasty"
.loop
	btst.b 	#DMAB_BLTDONE,DMACONR 		; check blitter busy flag
	bne.s 	.loop
	move.w	#$0400,DMACON				; disable blitter nasty
	rts

;
; void _lwmf_WaitVertBlank(void)
;

_lwmf_WaitVertBlank::
.wait  
	move.l	VPOSR,d0
    and.l	#$1FF00,d0
    cmp.l	#303<<8,d0
    bne.b	.wait						 
    rts

;
; void lwmf_ClearMemCPU(__reg("a1") long* StartAddress, __reg("d7") long NumberOfBytes);
;

_lwmf_ClearMemCPU::
	movem.l d2-d7/a2-a6,-(sp)       ; save all registers

	lea     zeros(pc),a0
	add.l   d7,a1                   ; we go top -> down
	lsr.l   #2,d7                   ; divide by 4
	move.l  d7,d6
	lsr.l   #7,d6                   ; get number of blocks of 128 long words 
	beq.s   .clear                  ; branch if we have no complete block
	subq.l  #1,d6                   ; one less to get loop working
	movem.l (a0),d0-d5/a2-a6        ; we use eight registers -> equals 32 bytes
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
	and.l   #$0F,d7                 ; check how many long words we still have
	beq.s   .done
	subq.l  #1,d7                   ; one less to get loop working
	move.l  (a0),a1
.setword
	move.l  d0,-(a1)                ; set memory by one long word at a time
	dbra    d7,.setword
.done
	movem.l (sp)+,d2-d7/a2-a6       ; restore registers
	rts

;
; void lwmf_ClearScreen(__reg("a1") long* StartAddress);
;

_lwmf_ClearScreen::
	movem.l d2-d7/a2-a6,-(sp)       ; save all registers

	; Clear first half of screen with blitter
	bsr     _lwmf_WaitBlitter
	moveq   #0,d0
	move.w  d0,BLTDMOD		       
	move.l  #$01000000,BLTCON0	  
	move.l  a1,BLTDPTH		       
	move.w  #SCREENCLRSIZEBLT,BLTSIZE

	; Clear rest of screen with cpu
	lea     zeros(pc),a0
	move.l  #SCREENCLRSIZECPU,d7
	add.l   d7,a1                   ; we go top -> down
	lsr.l   #3,d7                   ; divide by 8, we only need to clear half of the screen...
	move.l  d7,d6
	lsr.l   #7,d6                   ; get number of blocks of 128 long words 
	beq.s   .clear                  ; branch if we have no complete block
	subq.l  #1,d6                   ; one less to get loop working
	movem.l (a0),d0-d5/a2-a6        ; we use eight registers -> equals 32 bytes
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
	and.l   #$0F,d7                 ; check how many long words we still have
	beq.s   .done
	subq.l  #1,d7                   ; one less to get loop working
	move.l  (a0),a1
.setword
	move.l  d0,-(a1)                ; set memory by one long word at a time
	dbra    d7,.setword
.done
	movem.l (sp)+,d2-d7/a2-a6       ; restore registers
	rts

;
; void lwmf_SetPixel(__reg("d0") WORD PosX, __reg("d1") WORD PosY,  __reg("d2") UBYTE Color,  __reg("a0") long* Target);
;

_lwmf_SetPixel::
	movem.l d2-d4,-(sp)                         ; save registers

	muls.w  #SCREENWIDTHTOTAL,d1        		; address offset for line
	move.w  d0,d3			                    ; calc x position
	not.w   d3			       
	asr.w   #3,d0			                    ; byte offset for x position
	add.l   d0,d1
	moveq   #NUMBITPLANES-1,d4                  ; loop through bitplanes
.loop
	ror.b   #1,d2                               ; is bit already set?			       
	bpl.s   .skipbpl
	bset    d3,(a0,d1.l)	                    ; if not -> set it
.skipbpl
	lea     SCREENBROW(a0),a0	                ; next bitplane
	dbra    d4,.loop

	movem.l (sp)+,d2-d4                         ; restore registers
	rts

;
; void lwmf_BlitTile(__reg("a1") long* SrcAddr, __reg("d0") WORD SrcModulo, __reg("d1") long SrcOffset, __reg("a2") long* DstAddr, __reg("d2") WORD PosX, __reg("d3") WORD PosY, __reg("d4") WORD Width, __reg("d5") WORD Height);
;

_lwmf_BlitTile::
	movem.l d2-d6/a2,-(sp)						; save registers

	bsr     _lwmf_WaitBlitter

	subq.w	#2,d0								; subtract two more words because of barrel shift
	move.w  d0,BLTAMOD							; in general: SOURCE_BITMAP_WIDTH/8 - width in words

	move.w	#SCREENWIDTHTOTAL,d6				; TARGET_BITMAP_WIDTH/8 * NUMBITPLANES - WORDS
	sub.w	d4,d6								; subtract width in words
	subq.w	#2,d6								; subtract two more words because of barrel shift
	move.w  d6,BLTDMOD							; move complete modulo into target D							

	move.w	d2,d6								; store PosX for further use
	asr.w	#3,d6         						; arithmetic right shift PosX by three bits  
	mulu.w	#SCREENWIDTHTOTAL,d3         		; multiply PosY with target width
	add.l	d6,a2         						; add PosX to DstAddr
	add.l	d3,a2         						; add PosY to DstAddr
	move.l  a2,BLTDPTH							; DstAddr -> Blitter Destination D									       

	andi.w	#$F,d2        						; clear all but first byte of PosX
	ror.w	#4,d2								; rotate right by four bits
	add.w	#$09F0,d2     						; D = A ($F0), ascending mode
	move.w  d2,BLTCON0
	
	move.l	#$FFFF0000,BLTAFWM					; mask out first word	  
	
	add.l   d1,a1                   			; add source offset (in bytes) to SrcAddr
	move.l  a1,BLTAPTH							; SrcAddr -> Blitter Source A
		
	lsl.w	#6,d5								; multiply Height in lines by 64
	add.w	d4,d5								; add width in words to Height
	addq.w	#1,d5								; add one more word because of barrel shift
	move.w  d5,BLTSIZE              			; in general: number of lines * 64 + width in words

	movem.l (sp)+,d2-d6/a2						; restore registers
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

_GfxBase::
	dc.l    0

intuitionlib:
	dc.b    "intuition.library",0

_IntuitionBase::
	dc.l    0

datatypeslib:
	dc.b    "datatypes.library",0

_DataTypesBase::
	dc.l    0