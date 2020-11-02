; Various assembler functions for lwmf
; Code is compatible with Motorola syntax as provided by vbcc

; ***************************************************************************************************
; * Global                                                                                          *
; ***************************************************************************************************

; Labels

EXECBASE        = $4

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
CUSTOM		    = $DFF000   ; Base address of custom registers
DMACON          = $DFF096   ; DMA control (and blitter status) read/write
DMACONR         = $DFF002   ; DMA control (and blitter status) read
INTENA          = $DFF09A   ; Interrupt enable read/write
INTENAR         = $DFF01C   ; Interrupt enable read
INTREQ          = $DFF09C   ; Interrupt request read/write
INTREQR         = $DFF01E   ; Interrupr request read
VPOSR           = $DFF004   ; Read vert most sig. bits (and frame flop)

DEST 		    = $100      ; Blitter control register / destination

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

MINVERSION      = 39        ; Set required version (39 -> Amiga OS 3.0 and higher)

; ***************************************************************************************************
; * Functions                                                                                       *
; ***************************************************************************************************

; **************************************************************************
; * Library handling                                                       *
; **************************************************************************

;
; __reg("d0") ULONG lwmf_LoadGraphicsLibrary(void);
;

_lwmf_LoadGraphicsLibrary:
    move.l	EXECBASE,a6             ; Use exec base address
    lea     gfxlib,a1
    moveq   #MINVERSION,d0
    jsr     LVOOpenLibrary(a6)      ; Load graphics.library
    tst.l   d0                      ; Check if loading was successful
    bne.s   .open_ok
    moveq   #20,d0                  ; return with error
    rts
.open_ok:
    move.l  d0,_GfxBase             ; Store adress of GfxBase in variable
    moveq   #0,d0                   ; return with success
    rts

    public _lwmf_LoadGraphicsLibrary

;
; __reg("d0") ULONG lwmf_LoadIntuitionLibrary(void);
;

_lwmf_LoadIntuitionLibrary:
    move.l	EXECBASE,a6             ; Use exec base address
    lea     intuitionlib,a1
    moveq   #MINVERSION,d0
    jsr     LVOOpenLibrary(a6)      ; Load intuition.library
    tst.l   d0                      ; Check if loading was successful
    bne.s   .open_ok
    moveq   #20,d0                  ; return with error
    rts
.open_ok:
    move.l  d0,_IntuitionBase       ; Store adress of IntuitionBase in variable
    moveq   #0,d0                   ; return with success
    rts

    public _lwmf_LoadIntuitionLibrary

;
; __reg("d0") ULONG lwmf_LoadDatatypesLibrary(void);
;

_lwmf_LoadDatatypesLibrary:
    move.l	EXECBASE,a6             ; Use exec base address
    lea     datatypeslib,a1
    moveq   #MINVERSION,d0
    jsr     LVOOpenLibrary(a6)      ; Load datatypes.library
    tst.l   d0                      ; Check if loading was successful
    bne.s   .open_ok
    moveq   #20,d0                  ; return with error
    rts
.open_ok:
    move.l  d0,_DataTypesBase       ; Store adress of DataTypesBase in variable
    moveq   #0,d0                   ; return with success
    rts

    public _lwmf_LoadDatatypesLibrary

;
; void lwmf_CloseLibraries(void);
;

_lwmf_CloseLibraries:
    move.l  EXECBASE,a6             ; Use exec base address
    move.l  _DataTypesBase,a1       ; Use _DataTypesBase address in a1 for CloseLibrary             
    jsr     LVOCloseLibrary(a6)    
    move.l  #0,_DataTypesBase
    move.l  _IntuitionBase,a1       ; Use _IntuitionBase address in a1 for CloseLibrary             
    jsr     LVOCloseLibrary(a6)    
    move.l  #0,_IntuitionBase
    move.l  _GfxBase,a1             ; Use _GfxBase address in a1 for CloseLibrary             
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
    move.w  DMACONR,d0              ; Store current custom registers for later restore
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
    move.l  34(a6),oldview          ; Store current view
    move.l  38(a6),oldcopper        ; Store current copperlist
    move.l  #0,a1
    jsr     LVOLoadView(a6)	        ; LoadView(NULL)
    jsr     LVOWaitTOF(a6)
    jsr     LVOWaitTOF(a6)
    move.l	EXECBASE,a6
    jsr     LVOForbid(a6)
    rts

   	public _lwmf_TakeOverOS

;
; void lwmf_ReleaseOS(void);
;

_lwmf_ReleaseOS:
    move.w  #$7FFF,DMACON
    move.w  olddma,DMACON
    move.w  #$7FFF,INTENA
    move.w  oldintena,INTENA
    move.w  #$7FFF,INTREQ
    move.w  oldintreq,INTREQ
    move.w  #$7FFF,ADKCON
    move.w  oldadkcon,ADKCON

    move.l  oldcopper,COP1LCH       ; Restore system copperlist
    move.l  _GfxBase,a6             ; Use graphics.library base address
    move.l  oldview,a1              ; Restore saved view
    jsr     LVOLoadView(a6)         ; LoadView(oldview)
    jsr     LVOWaitTOF(a6)          
    jsr     LVOWaitTOF(a6)         
    move.l  EXECBASE,a6             ; Use exec base address
    jsr     LVOPermit(a6)
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
    bne 	.loop
    rts

	public _lwmf_WaitBlitter

;
; void _lwmf_WaitVertBlank(void)
;

_lwmf_WaitVertBlank:
.loop: 
    move.l  VPOSR,d0
	and.l   #$1FF00,d0
	cmp.l   #303<<8,d0          ; Check if line 303 is reached
	bne.s   .loop
.loop2:                         ; Second check for A4000 compatibility
	move.l  VPOSR,d0
	and.l   #$1FF00,d0
	cmp.l   #303<<8,d0
	beq.s   .loop2
	rts

	public _lwmf_WaitVertBlank
	
;
; void lwmf_ClearMem(__reg("a0") long* Address, __reg("d0") long NumberOfBytes);
;

_lwmf_ClearMem:
    lsr.l   #5,d0               ; Shift right by 5 -> Division by 32
    subq    #1,d0               ; Subtract 1
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

    public _lwmf_ClearMem

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