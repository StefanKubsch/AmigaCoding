
	machine	68000							; assemble for Motorola 68000

COLUMN_TORSION_SHIFT	equ	7					; fixed point shift for phase accumulator
COLUMN_PHASE_STRIDE	equ	32					; 16 words per phase pointer entry
COPPER_LINE_BYTES	equ	44					; wait and ten pointer moves per scanline

; void UpdateTwistCopperRangeAsm(a0 = UWORD *CopperData,
;                                a1 = const UWORD *PhaseWords,
;                                d0 = LONG AccStart,
;                                d1 = WORD PhaseDelta,
;                                d2 = UWORD PhaseAdd,
;                                d3 = UWORD Count);
;
; CopperData points to the first BPL1PTH data word of the first scanline.
; PhaseWords contains 256 padded entries of 16 words each. The first ten words
; are high/low pointer words for BPL1..BPL5. PhaseDelta is the per-scanline
; accumulator step. PhaseAdd contains the global upward scroll phase.

_UpdateTwistCopperRangeAsm::
	movem.l	d2-d7/a2,-(sp)					; save non-scratch registers used by the routine

	move.l	d0,d4						; d4 = signed phase accumulator
	move.w	d1,d6						; d6 = signed phase delta per scanline
	ext.l	d6						; extend phase delta to 32 bits
	move.w	d2,d5						; d5 = global upward scroll phase
	move.w	d3,d7						; d7 = scanline count
	subq.w	#1,d7						; convert count into DBRA loop counter

.rowloop:
	move.l	d4,d0						; d0 = accumulator copy
	asr.l	#COLUMN_TORSION_SHIFT,d0			; convert accumulator to row phase offset
	add.w	d5,d0						; add monotonic upward scroll phase
	and.w	#$00ff,d0					; keep phase in 0..255 range

	lsl.w	#5,d0						; convert phase to byte offset in pointer table
	lea	0(a1,d0.w),a2					; a2 = pointer words for this row phase
	move.w	(a2)+,(a0)					; update BPL1PTH data word
	move.w	(a2)+,4(a0)					; update BPL1PTL data word
	move.w	(a2)+,8(a0)					; update BPL2PTH data word
	move.w	(a2)+,12(a0)					; update BPL2PTL data word
	move.w	(a2)+,16(a0)					; update BPL3PTH data word
	move.w	(a2)+,20(a0)					; update BPL3PTL data word
	move.w	(a2)+,24(a0)					; update BPL4PTH data word
	move.w	(a2)+,28(a0)					; update BPL4PTL data word
	move.w	(a2)+,32(a0)					; update BPL5PTH data word
	move.w	(a2)+,36(a0)					; update BPL5PTL data word

	add.l	d6,d4						; advance phase accumulator for next scanline
	lea	COPPER_LINE_BYTES(a0),a0				; advance to next copper line data block
	dbra	d7,.rowloop					; process next scanline

	movem.l	(sp)+,d2-d7/a2					; restore saved registers
	rts							; return to C caller
