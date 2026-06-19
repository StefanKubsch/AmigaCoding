	machine	68000						; assemble for Motorola 68000

	include "lwmf/lwmf_hardware_regs.i"	; use shared OCS hardware register definitions

COLUMN_TORSION_SHIFT	equ	7			; fixed point shift for phase accumulator
COLUMN_PHASE_STRIDE		equ	32			; 16 words per phase/text row entry
COPPER_LINE_BYTES		equ	60			; wait, four color moves and ten pointer moves per scanline
TEXT_TEXTURE_MASK		equ	15			; 16 texture rows, 8 font rows plus 8 empty rows

; void UpdateTwistCopperTextRangeAsm(a0 = UWORD *CopperData,
;                                    a1 = const UWORD *PhaseWords,
;                                    d0 = LONG AccStart,
;                                    d1 = WORD PhaseDelta,
;                                    d2 = UWORD PhaseAdd,
;                                    d3 = UWORD TextAdd,
;                                    d4 = UWORD Count);
;
; CopperData points to the first COLOR01 data word of the first scanline.
; PhaseWords contains 16 texture rows with 256 phase entries each. Every entry
; has 16 words: four COLOR01..COLOR04 data words, ten bitplane pointer words
; and two padding words. PhaseDelta is the per-scanline twist accumulator step.
; PhaseAdd moves the twisted surface. TextAdd moves the projected text upward.

_UpdateTwistCopperTextRangeAsm::
	movem.l	d2-d7/a2,-(sp)				; save non-scratch registers used by the routine

	move.l	d0,d6						; d6 = signed phase accumulator
	move.w	d1,d5						; d5 = signed phase delta per scanline
	ext.l	d5							; extend phase delta to 32 bits
	move.w	d4,d7						; d7 = scanline count
	subq.w	#1,d7						; convert count into DBRA loop counter

.rowloop:
	move.l	d6,d0						; d0 = accumulator copy
	asr.l	#COLUMN_TORSION_SHIFT,d0	; convert accumulator to row phase offset
	add.w	d2,d0						; add surface scroll phase
	and.l	#$000000ff,d0				; keep phase in 0..255 range

	moveq	#0,d1						; clear combined phase/text index
	move.w	d3,d1						; d1 = text row accumulator
	and.w	#TEXT_TEXTURE_MASK,d1		; keep texture row in 0..15 range
	lsl.w	#8,d1						; text row selects a 256 phase block
	or.w	d0,d1						; combine text row and phase
	lsl.l	#5,d1						; convert 16-word entry index to byte offset
	lea	0(a1,d1.l),a2					; a2 = color and pointer words for this row

	move.w	(a2)+,(a0)					; update COLOR01 data word
	move.w	(a2)+,4(a0)					; update COLOR02 data word
	move.w	(a2)+,8(a0)					; update COLOR03 data word
	move.w	(a2)+,12(a0)				; update COLOR04 data word
	move.w	(a2)+,16(a0)				; update BPL1PTH data word
	move.w	(a2)+,20(a0)				; update BPL1PTL data word
	move.w	(a2)+,24(a0)				; update BPL2PTH data word
	move.w	(a2)+,28(a0)				; update BPL2PTL data word
	move.w	(a2)+,32(a0)				; update BPL3PTH data word
	move.w	(a2)+,36(a0)				; update BPL3PTL data word
	move.w	(a2)+,40(a0)				; update BPL4PTH data word
	move.w	(a2)+,44(a0)				; update BPL4PTL data word
	move.w	(a2)+,48(a0)				; update BPL5PTH data word
	move.w	(a2)+,52(a0)				; update BPL5PTL data word

	add.l	d5,d6						; advance twist accumulator for next scanline
	addq.w	#1,d3						; advance projected text row upward
	lea	COPPER_LINE_BYTES(a0),a0		; advance to next copper line data block
	dbra	d7,.rowloop					; process next scanline

	movem.l	(sp)+,d2-d7/a2				; restore saved registers
	rts									; return to C caller
