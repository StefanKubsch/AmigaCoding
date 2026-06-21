	machine	68000						; assemble for Motorola 68000

	include "lwmf/lwmf_hardware_regs.i"	; use shared OCS hardware register definitions

COLUMN_TORSION_SHIFT	equ	7			; fixed point shift for phase accumulator
COLUMN_PHASE_STRIDE		equ	32			; 16 words per phase/text row entry
COPPER_LINE_BYTES		equ	52			; wait, four color moves and eight pointer moves per scanline
TEXT_TEXTURE_MASK		equ	15			; 16 texture rows, 8 font rows plus 8 empty rows
COLUMN_SPLIT_ROW		equ	188			; SCREENHEIGHT - VPOS_OFFSET - COLUMN_TOP
COLUMN_SPLIT_HEIGHT		equ	20			; COLUMN_HEIGHT - COLUMN_SPLIT_ROW

; void UpdateTwistCopperTextAsm(a0 = UWORD *CopperDataLow,
;                               a1 = UWORD *CopperDataHigh,
;                               a2 = const UWORD *PhaseWords,
;                               d0 = WORD AccStartLow,
;                               d1 = WORD PhaseDelta,
;                               d2 = UWORD PhaseAdd,
;                               d3 = UWORD TextAdd);
;
; CopperDataLow/CopperDataHigh point to the first COLOR01 data word of the
; two copper body ranges split by the VPOS-255 skip. PhaseWords contains 16
; texture rows with 256 phase entries each. Every entry has 16 words: four
; COLOR01..COLOR04 data words, eight bitplane pointer words and four padding
; words. BPL5 stays blank. With the current 208-line setup the twist
; accumulator stays inside signed 16-bit range.

_UpdateTwistCopperTextAsm::
	movem.l	d3/d5-d7/a3,-(sp)			; save non-scratch registers changed by the routine

	move.w	d0,d6						; d6 = signed 16-bit phase accumulator
	move.w	d1,d5						; d5 = signed phase delta per scanline
	move.w	#COLUMN_SPLIT_ROW-1,d7		; first DBRA range before the VPOS-255 skip
	bsr.s	.patch_lines

	move.l	a1,a0						; continue with the high copper body range
	move.w	#COLUMN_SPLIT_HEIGHT-1,d7
	bsr.s	.patch_lines

	movem.l	(sp)+,d3/d5-d7/a3			; restore saved registers
	rts									; return to C caller

.patch_lines:
	move.w	d6,d0						; d0 = accumulator copy
	asr.w	#COLUMN_TORSION_SHIFT,d0	; convert accumulator to row phase offset
	add.w	d2,d0						; add surface scroll phase
	and.w	#$00ff,d0					; keep phase in 0..255 range

	moveq	#TEXT_TEXTURE_MASK,d1		; d1 = texture mask with upper word already clear
	and.w	d3,d1						; keep texture row in 0..15 range
	lsl.w	#8,d1						; text row selects a 256 phase block
	or.w	d0,d1						; combine text row and phase
	lsl.l	#5,d1						; convert 16-word entry index to byte offset
	lea	0(a2,d1.l),a3					; a3 = color and pointer words for this row

	move.w	(a3)+,(a0)					; update COLOR01 data word
	move.w	(a3)+,4(a0)					; update COLOR02 data word
	move.w	(a3)+,8(a0)					; update COLOR03 data word
	move.w	(a3)+,12(a0)				; update COLOR04 data word
	move.w	(a3)+,16(a0)				; update BPL1PTH data word
	move.w	(a3)+,20(a0)				; update BPL1PTL data word
	move.w	(a3)+,24(a0)				; update BPL2PTH data word
	move.w	(a3)+,28(a0)				; update BPL2PTL data word
	move.w	(a3)+,32(a0)				; update BPL3PTH data word
	move.w	(a3)+,36(a0)				; update BPL3PTL data word
	move.w	(a3)+,40(a0)				; update BPL4PTH data word
	move.w	(a3)+,44(a0)				; update BPL4PTL data word

	add.w	d5,d6						; advance twist accumulator for next scanline
	addq.w	#1,d3						; advance projected text row upward
	lea	COPPER_LINE_BYTES(a0),a0		; advance to next copper line data block
	dbra	d7,.patch_lines				; process next scanline
	rts
