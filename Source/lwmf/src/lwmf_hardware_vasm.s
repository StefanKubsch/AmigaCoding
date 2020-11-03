; Various assembler functions for lwmf
; Code is compatible with Motorola syntax as provided by vbcc

; ***************************************************************************************************
; * Global                                                                                          *
; ***************************************************************************************************

; Screen stuff
; Needs to be changed according to your needs!

WIDTH           = 320
HEIGHT          = 256
NUMBITPLANES    = 3
BPLSIZE         = WIDTH/16*2
MODULO          = BPLSIZE*NUMBITPLANES	

; Labels

EXECBASE        = $4
CUSTOM		    = $DFF000   ; Base address of custom registers

ADKCON          = $DFF09E   ; Audio/Disk control read/write
ADKCONR         = $DFF010   ; Audio/Disk control read
BLTCON0 	    = $DFF040   ; Blitter control reg 0
BLTCON1 	    = $DFF042   ; Blitter control reg 1
BLTDPTH		    = $DFF054   ; Blitter pointer to destination D (high 5 bits)
BLTDPTL         = $DFF056   ; Blitter pointer to destination D (low 15 bits)
BLTDMOD 	    = $DFF066   ; Blitter modulo for destination D
BLTSIZE 	    = $DFF058   ; Blitter start and size (win/width, height)
COP1LCH         = $DFF080   ; Coprocessor first location register (high 5 bits)
COP1LCL         = $DFF082   ; Coprocessor first location register (low 15 bits)
DMACON          = $DFF096   ; DMA control (and blitter status) read/write
DMACONR         = $DFF002   ; DMA control (and blitter status) read
INTENA          = $DFF09A   ; Interrupt enable read/write
INTENAR         = $DFF01C   ; Interrupt enable read
INTREQ          = $DFF09C   ; Interrupt request read/write
INTREQR         = $DFF01E   ; Interrupr request read
VPOSR           = $DFF004   ; Read vert most sig. bits (and frame flop)

DMAB_BLTDONE    = 14        ; DMACONR bit 14 - blitter busy flag

; Library vector offsets (LVO)

; graphics.library
LVOLoadView     = -222
LVOWaitTOF      = -270
; exec.library
LVOForbid       = -132
LVOPermit       = -138
LVOOpenLibrary  = -552
LVOCloseLibrary = -414

; Declare external variables

    XDEF _GfxBase
    XDEF _IntuitionBase
    XDEF _DataTypesBase

; Constants

MINVERSION      = 39        ; set required version (39 -> Amiga OS 3.0 and higher)

; ***************************************************************************************************
; * Functions                                                                                       *
; ***************************************************************************************************

; Some words about registers
;
; a0,a1,d0,d1 are "scratch" registers - you can do what you want with 'em
; All other registers need to be saved before used in a function, and must be restored before returning
; Libraries expect their respective base address in a6

; **************************************************************************
; * Library handling                                                       *
; **************************************************************************

;
; __reg("d0") ULONG lwmf_LoadLibraries(void);
;

_lwmf_LoadLibraries:
    movem.l a6,-(sp)                ; save register on stack

    move.l	EXECBASE.w,a6           ; use exec base address
    
    lea     gfxlib,a1               ; load graphics.library
    moveq   #MINVERSION,d0
    jsr     LVOOpenLibrary(a6)      
    tst.l   d0                      ; check if loading was successful
    beq.s   .open_failed            ; if d0 == 0 then failed
    move.l  d0,_GfxBase             ; store adress of GfxBase in variable
    
    lea     intuitionlib,a1         ; load intuition.library
    moveq   #MINVERSION,d0
    jsr     LVOOpenLibrary(a6)      
    tst.l   d0                      
    beq.s   .open_failed
    move.l  d0,_IntuitionBase       

    lea     datatypeslib,a1         ; load datatypes.library
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
    movea.l (sp)+,a6                ; restore registers
    rts

    public _lwmf_LoadLibraries

;
; void lwmf_CloseLibraries(void);
;

_lwmf_CloseLibraries:
    move.l  EXECBASE.w,a6           ; use exec base address
    move.l  _DataTypesBase,d0       ; use _DataTypesBase address in a1 for CloseLibrary     
    tst.l   d0
    bne.s   .closedatatypelib

    move.l  _IntuitionBase,d0       ; use _IntuitionBase address in a1 for CloseLibrary      
    tst.l   d0  
    bne.s   .closeintuitionlib

    move.l  _GfxBase,d0             ; use _GfxBase address in a1 for CloseLibrary                         
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

    public _lwmf_CloseLibraries

; **************************************************************************
; * System take over                                                       *
; **************************************************************************

;
; void lwmf_TakeOverOS(void);
;

_lwmf_TakeOverOS:
    movem.l a6,-(sp)                ; save register on stack

    move.w  DMACONR,d0              ; store current custom registers for later restore
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

    move.l  _GfxBase,a6
    move.l  34(a6),oldview          ; store current view
    move.l  38(a6),oldcopper        ; store current copperlist
    suba.l  a1,a1
    jsr     LVOLoadView(a6)	        ; LoadView(NULL)
    jsr     LVOWaitTOF(a6)
    jsr     LVOWaitTOF(a6)
    move.l	EXECBASE.w,a6
    jsr     LVOForbid(a6)

    movea.l (sp)+,a6                ; restore registers
    rts

   	public _lwmf_TakeOverOS

;
; void lwmf_ReleaseOS(void);
;

_lwmf_ReleaseOS:
    movem.l a6,-(sp)                ; save register on stack

    move.w  #$7FFF,DMACON
    move.w  olddma,DMACON
    move.w  #$7FFF,INTENA
    move.w  oldintena,INTENA
    move.w  #$7FFF,INTREQ
    move.w  oldintreq,INTREQ
    move.w  #$7FFF,ADKCON
    move.w  oldadkcon,ADKCON

    move.l  oldcopper,COP1LCH       ; restore system copperlist
    move.l  _GfxBase,a6             ; use graphics.library base address
    move.l  oldview,a1              ; restore saved view
    jsr     LVOLoadView(a6)         ; loadView(oldview)
    jsr     LVOWaitTOF(a6)          
    jsr     LVOWaitTOF(a6)         
    move.l  EXECBASE.w,a6           ; use exec base address
    jsr     LVOPermit(a6)

    movea.l (sp)+,a6                ; restore registers
   	rts

    public _lwmf_ReleaseOS

; **************************************************************************
; * System functions                                                       *
; **************************************************************************

;
; void _lwmf_WaitBlitter(void)
;

_lwmf_WaitBlitter:
    btst.b  #DMAB_BLTDONE-8,DMACONR 		; check against DMACONR
.loop:                                      ; check twice, bug in A1000
    btst.b 	#DMAB_BLTDONE-8,DMACONR 		
    bne.b 	.loop
    rts

	public _lwmf_WaitBlitter

;
; void _lwmf_WaitVertBlank(void)
;

_lwmf_WaitVertBlank:
.loop: 
    move.l  VPOSR,d0
	and.l   #$1FF00,d0
	cmp.l   #303<<8,d0          ; check if line 303 is reached
	bne.s   .loop
.loop2:                         ; check if line 303 is passed
	move.l  VPOSR,d0
	and.l   #$1FF00,d0
	cmp.l   #303<<8,d0
	beq.s   .loop2
	rts

	public _lwmf_WaitVertBlank
	
;
; void lwmf_ClearMemCPU(__reg("a0") long* Address, __reg("d0") long NumberOfBytes);
;

_lwmf_ClearMemCPU:
    lsr.l   #5,d0               ; shift right by 5 -> division by 32
    subq.l  #1,d0               ; subtract 1
    moveq   #0,d1
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

    public _lwmf_ClearMemCPU

;
; void lwmf_ClearMemCPU2(__reg("a0") long* Address, __reg("d7") long NumberOfBytes);
;

_lwmf_ClearMemCPU2:
    movem.l d2-d6/a2-a4,-(sp)   ; save all registers
    lea     zeros,a1
    add.l   d7,a0               ; we go top -> down
    lsr.l   #2,d7               ; divide by 4 for long words
    move.l  d7,d6
    lsr.l   #4,d6               ; number of 16 longword blocks 
    beq.s   .clear              ; branch if we have no block
    subq.l  #1,d6               ; one less to get loop working
    movem.l (a1),d0-d4/a2-a4    ; we use eight registers -> equals 32 bytes
.clearblock:
    movem.l d0-d4/a2-a4,-(a0)   ; 8 registers -> clear 32 bytes at once
    movem.l d0-d4/a2-a4,-(a0)   ; and again
    dbra    d6,.clearblock
.clear:
    and.w   #$0F,d7             ; check how many words we still have
    beq.s   .done
    subq.w  #1,d7               ; one less to get loop working
    move.l  (a1),a0
.setword:
    move.l  d0,-(a0)            ; set memory long word at a time
    dbra    d7,.setword
.done:
    movem.l (sp)+,d2-d6/a2-a4   ; restore registers
    rts

    public _lwmf_ClearMemCPU2

;
; void lwmf_SetPixel(__reg("d1") word PosX, __reg("d2") word PosY,  __reg("d3") word Color,  __reg("a1") long* Target);
;

_lwmf_SetPixel:
	movem.l d2-d5,-(sp)             ; save all registers

	muls    #MODULO,d2			    ; address offset for line
	move.w  d1,d4			        ; calc x position
	not.w   d4			       
	asr.w   #3,d1			        ; byte offset for x position
	ext.l   d1			       
	add.l   d1,d2
	moveq   #NUMBITPLANES,d5        ; loop through bitplanes
    subq    #1,d5
.loop:	
    ror.b   #1,d3                   ; is bit already set?			       
    bpl.s   .skipbpl
	bset    d4,(a1,d2)	            ; if not -> set it
.skipbpl:
	lea     BPLSIZE(a1),a1		    ; next bitplane
	dbf     d5,.loop

	movem.l (sp)+,d2-d5             ; restore registers
	rts

    public _lwmf_SetPixel

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
_GfxBase:
    dc.l    0

intuitionlib:
    dc.b "intuition.library",0
    even
_IntuitionBase:
    dc.l    0

datatypeslib:
    dc.b "datatypes.library",0
    even
_DataTypesBase:
    dc.l    0