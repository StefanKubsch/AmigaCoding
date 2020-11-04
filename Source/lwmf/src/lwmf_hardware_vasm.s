; Various assembler functions for lwmf
; Code is compatible with Motorola syntax as provided by vbcc

; ***************************************************************************************************
; * Global                                                                                          *
; ***************************************************************************************************

; Screen stuff
; Needs to be changed according to your needs!

WIDTH           =     320
HEIGHT          =     256
NUMBITPLANES    =     3
BPLSIZE         =     WIDTH/16*2
MODULO          =     BPLSIZE*NUMBITPLANES	

; Custom registers

EXECBASE        =     $4
CUSTOM		    =     $00DFF000 ; Base address of custom registers

ADKCON          =     $09E      ; Audio/Disk control read/write
ADKCONR         =     $010      ; Audio/Disk control read
BLTCON0 	    =     $040      ; Blitter control reg 0
BLTCON1 	    =     $042      ; Blitter control reg 1
BLTDPTH		    =     $054      ; Blitter pointer to destination D (high 5 bits)
BLTDPTL         =     $056      ; Blitter pointer to destination D (low 15 bits)
BLTDMOD 	    =     $066      ; Blitter modulo for destination D
BLTSIZE 	    =     $058      ; Blitter start and size (win/width, height)
COP1LCH         =     $080      ; Coprocessor first location register (high 5 bits)
COP1LCL         =     $082      ; Coprocessor first location register (low 15 bits)
DMACON          =     $096      ; DMA control (and blitter status) read/write
DMACONR         =     $002      ; DMA control (and blitter status) read
INTENA          =     $09A      ; Interrupt enable read/write
INTENAR         =     $01C      ; Interrupt enable read
INTREQ          =     $09C      ; Interrupt request read/write
INTREQR         =     $01E      ; Interrupr request read
VPOSR           =     $004      ; Read vert most sig. bits (and frame flop)

DMAB_BLTDONE    =     14        ; DMACONR bit 14 - blitter busy flag

; Library vector offsets (LVO)

; graphics.library
LVOLoadView     =     -222
LVOWaitTOF      =     -270
; exec.library
LVOForbid       =     -132
LVOPermit       =     -138
LVOOpenLibrary  =     -552
LVOCloseLibrary =     -414

; Constants

MINVERSION      =     39        ; set required version (39 -> Amiga OS 3.0 and higher)

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
.open_failed:
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
.closedatatypelib:
    move.l  d0,a1                           
    jsr     LVOCloseLibrary(a6) 
    move.l  #0,_DataTypesBase
    rts
.closeintuitionlib:
    move.l  d0,a1                           
    jsr     LVOCloseLibrary(a6)    
    move.l  #0,_IntuitionBase
    rts
.closegraphicslib:
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

    lea     CUSTOM,a0
    move.w  DMACONR(a0),d0          ; store current custom registers for later restore
    or.w    #$8000,d0
    move.w  d0,olddma
    move.w  INTENAR(a0),d0
    or.w    #$8000,d0
    move.w  d0,oldintena
    move.w  INTREQR(a0),d0
    or.w    #$8000,d0
    move.w  d0,oldintreq
    move.w  ADKCONR(a0),d0
    or.w    #$8000,d0
    move.w  d0,oldadkcon

    move.l  _GfxBase(pc),a6
    move.l  34(a6),oldview          ; store current view
    move.l  38(a6),oldcopper        ; store current copperlist
    suba.l  a1,a1                   ; Set a1 to zero
    jsr     LVOLoadView(a6)	        ; LoadView(NULL)
    jsr     LVOWaitTOF(a6)
    jsr     LVOWaitTOF(a6)
    move.l	EXECBASE.w,a6
    jsr     LVOForbid(a6)

    movea.l (sp)+,a6                ; restore register
    rts

;
; void lwmf_ReleaseOS(void);
;

_lwmf_ReleaseOS::
    movem.l a6,-(sp)                    ; save register on stack

    lea     CUSTOM,a0
    move.w  #$7FFF,DMACON(a0)
    move.w  olddma(pc),DMACON(a0)
    move.w  #$7FFF,INTENA(a0)
    move.w  oldintena(pc),INTENA(a0)
    move.w  #$7FFF,INTREQ(a0)
    move.w  oldintreq(pc),INTREQ(a0)
    move.w  #$7FFF,ADKCON(a0)
    move.w  oldadkcon(pc),ADKCON(a0)

    move.l  oldcopper(pc),COP1LCH(a0)   ; restore system copperlist
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
    lea     CUSTOM,a0
    btst.b  #DMAB_BLTDONE-8,DMACONR(a0) 	; check against DMACONR
.loop:                                      ; check twice, bug in A1000
    btst.b 	#DMAB_BLTDONE-8,DMACONR(a0) 		
    bne.s 	.loop
    rts

;
; void _lwmf_WaitVertBlank(void)
;

_lwmf_WaitVertBlank::
    lea     CUSTOM,a0
.loop: 
    move.l  VPOSR(a0),d0        ; check if line 303 is reached
	and.l   #$0001FF00,d0
	cmp.l   #303<<8,d0          
	bne.s   .loop
.loop2:                         ; check if line 303 is passed
	move.l  VPOSR(a0),d0
	and.l   #$0001FF00,d0
	cmp.l   #303<<8,d0
	beq.s   .loop2
	rts

;
; void lwmf_ClearMemCPU(__reg("a0") long* Address, __reg("d7") long NumberOfBytes);
;

_lwmf_ClearMemCPU::
    movem.l d2-d6/a2-a4,-(sp)       ; save all registers
    lea     zeros(pc),a1
    add.l   d7,a0                   ; we go top -> down
    lsr.l   #2,d7                   ; divide by 4 for long words
    move.l  d7,d6
    lsr.l   #4,d6                   ; number of 16 long word blocks 
    beq.s   .clear                  ; branch if we have no complete block
    subq.l  #1,d6                   ; one less to get loop working
    movem.l (a1),d0-d4/a2-a4        ; we use eight registers -> equals 32 bytes
.clearblock:
    movem.l d0-d4/a2-a4,-(a0)       ; 8 registers -> clear 32 bytes at once
    movem.l d0-d4/a2-a4,-(a0)       ; and again
    dbra    d6,.clearblock
.clear:
    and.l   #$0F,d7                 ; check how many words we still have
    beq.s   .done
    subq.l  #1,d7                   ; one less to get loop working
    move.l  (a1),a0
.setword:
    move.l  d0,-(a0)                ; set memory by one long word at a time
    dbra    d7,.setword
.done:
    movem.l (sp)+,d2-d6/a2-a4       ; restore registers
    rts

;
; void lwmf_SetPixel(__reg("d1") WORD PosX, __reg("d2") WORD PosY,  __reg("d3") WORD Color,  __reg("a1") long* Target);
;

_lwmf_SetPixel::
	movem.l d4-d5,-(sp)             ; save all registers

	muls.w  #MODULO,d2			    ; address offset for line
	move.w  d1,d4			        ; calc x position
	not.w   d4			       
	asr.w   #3,d1			        ; byte offset for x position
	ext.l   d1			       
	add.l   d1,d2
	moveq   #NUMBITPLANES-1,d5      ; loop through bitplanes
.loop:	
    ror.b   #1,d3                   ; is bit already set?			       
    bpl.s   .skipbpl
	bset    d4,(a1,d2)	            ; if not -> set it
.skipbpl:
	lea     BPLSIZE(a1),a1		    ; next bitplane
	dbra    d5,.loop

	movem.l (sp)+,d4-d5             ; restore registers
	rts

; ***************************************************************************************************
; * Variables                                                                                       *
; ***************************************************************************************************

;
; ClearMemCPU
;

zeros:
    dc.l    0,0,0,0,0,0,0,0

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
    dc.b "graphics.library",0
    even
_GfxBase::
    dc.l    0

intuitionlib:
    dc.b "intuition.library",0
    even
_IntuitionBase::
    dc.l    0

datatypeslib:
    dc.b "datatypes.library",0
    even
_DataTypesBase::
    dc.l    0