; Various assembler functions for lwmf
; Code is compatible with Motorola syntax as provided by vbcc
;
; Coded in 2020-2026 by Stefan Kubsch

	machine	68020

; ***************************************************************************************************
; * Functions                                                                                       *
; ***************************************************************************************************

;
; ULONG lwmf_Random(void);
;

_lwmf_Random::
	move.w	seed(PC),d0
    mulu    #$4E35,d0
	addq.w	#1,d0
    move.w  d0,seed
    rts

; ***************************************************************************************************
; * Variables                                                                                       *
; ***************************************************************************************************

seed:
	dc.l    $12345678