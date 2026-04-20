; Hardware register and constant definitions for OCS/Amiga
; Include this file in any assembly source that needs hardware register access.
; Pure EQU constants — no code, no machine-specific directives.
;
; Coded in 2020-2026 by Stefan Kubsch / Deep4

; ***************************************************************************************************
; * Global                                                                                          *
; ***************************************************************************************************

; Screen stuff
; Change it according to your needs!
;
; Export constants to "lwmf_Defines.h" for further use in C
; vasmm68k_mot -Fcdef -o ".\lwmf\Defines.h" ".\lwmf\lwmf_hardware_vasm.s"

SCREENWIDTH         equ     320
SCREENHEIGHT        equ     256
NUMBEROFBITPLANES   equ     2

BYTESPERROW			equ     SCREENWIDTH/8
SCREENWIDTHTOTAL	equ		BYTESPERROW*NUMBEROFBITPLANES
SCREENCLRSIZEBLT    equ     128*NUMBEROFBITPLANES*64+BYTESPERROW/2      ; half screen size for blitter part of screen clear (top -> mid)
SCREENCLRSIZECPU    equ     SCREENWIDTHTOTAL*SCREENHEIGHT			 	; size for cpu part of screen clear ( bottom -> mid)

; CUSTOMREGS registers

EXECBASE            equ     $4
SYSBASE         	equ     $4

CUSTOMREGS		    equ     $00DFF000		; Base address of CUSTOM registers

ATTNFLAGS       	equ     296				; ExecBase->AttnFlags

ADKCON              equ     $00DFF09E		; Audio/Disk control read/write
ADKCONR             equ     $00DFF010		; Audio/Disk control read
BLTCON0 	        equ     $00DFF040		; Blitter control reg 0
BLTCON1 	        equ     $00DFF042		; Blitter control reg 1
BLTAFWM             equ     $00DFF044		; Blitter first word mask for source A
BLTALWM             equ     $00DFF046		; Blitter last word mask for source A
BLTCPTH             equ     $00DFF048		; Blitter pointer to source C (high 5 bits)
BLTCPTL             equ     $00DFF04A		; Blitter pointer to source C (low 15 bits)
BLTBPTH             equ     $00DFF04C		; Blitter pointer to source B (high 5 bits)
BLTBPTL             equ     $00DFF04E		; Blitter pointer to source B (low 15 bits)
BLTAPTH             equ     $00DFF050		; Blitter pointer to source A (high 5 bits)
BLTAPTL             equ     $00DFF052		; Blitter pointer to source A (low 15 bits) / line-mode error term
BLTDPTH		        equ     $00DFF054		; Blitter pointer to destination D (high 5 bits)
BLTDPTL             equ     $00DFF056		; Blitter pointer to destination D (low 15 bits)
BLTSIZE 	        equ     $00DFF058		; Blitter start and size (win/width, height)
BLTCMOD             equ     $00DFF060		; Blitter modulo for source C
BLTBMOD             equ     $00DFF062		; Blitter modulo for source B
BLTAMOD             equ     $00DFF064		; Blitter modulo for source A
BLTDMOD 	        equ     $00DFF066		; Blitter modulo for D
BLTBDAT             equ     $00DFF072		; Blitter data for source B
BLTADAT             equ     $00DFF074		; Blitter data for source A
COP1LCH             equ     $00DFF080		; Coprocessor first location register (high 5 bits)
DMACON              equ     $00DFF096		; DMA control (and blitter status) read/write
DMACONR             equ     $00DFF002		; DMA control (and blitter status) read
INTENA              equ     $00DFF09A		; Interrupt enable read/write
INTENAR             equ     $00DFF01C		; Interrupt enable read
INTREQ              equ     $00DFF09C		; Interrupt request read/write
INTREQR             equ     $00DFF01E		; Interrupt request read
VPOSR               equ     $00DFF004		; Read vert most sig. bits (and frame flop)

DMAB_BLITTER        equ		6				; DMACONR bit 6 of high byte = blitter busy flag

; Library vector offsets (LVO)

; graphics.library
LVOLoadView         equ     -222
LVOWaitTOF          equ     -270

; exec.library
LVOForbid           equ     -132
LVOPermit           equ     -138
LVOOpenLibrary      equ     -552
LVOCloseLibrary     equ     -414
LVOSupervisor       equ     -30

; Constants

MINVERSION          equ     34        ; set required version (34 -> Kickstart 1.3 and higher)
GFX_ACTIVIEW        equ     34        ; GfxBase offset: pointer to active View
GFX_COPINIT         equ     38        ; GfxBase offset: system copper list pointer
DMASET_DEMO         equ     $83C0     ; SET | DMAEN | BPLEN | COPEN | BLTEN (no sprites)

; Magic constants

WORD_ALIGN_MASK      EQU $FFF0
BLTCON0_COPY_A_TO_D  EQU $09F0
