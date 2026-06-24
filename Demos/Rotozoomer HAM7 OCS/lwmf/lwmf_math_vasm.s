; Various assembler functions for lwmf
; Code is compatible with Motorola syntax as provided by vbcc
;
; Coded in 2020-2026 by Stefan Kubsch

	machine	68000

; ***************************************************************************************************
; * Functions                                                                                       *
; ***************************************************************************************************

;
; ULONG lwmf_Random(void);
;

_lwmf_Random::
	move.w	seed(PC),d0					; load current 16-bit seed
	mulu.w	#$4E35,d0					; advance linear congruential state
	addq.w	#1,d0						; add increment
	move.w	d0,seed						; store new 16-bit seed
	rts									; return random value in d0

; ***************************************************************************************************
; * Variables                                                                                       *
; ***************************************************************************************************

seed:
	dc.l	$12345678					; initial seed
