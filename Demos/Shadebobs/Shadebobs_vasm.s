; Shadebob fast frame draw functions
; Amiga 500 OCS / 68000 - vasm Motorola syntax
;
; (C) 2026 by Stefan Kubsch / Deep4
;

	machine 68000

	include "lwmf/lwmf_hardware_regs.i"

; ---------------------------------------------------------------------------
; Shadebob constants
; ---------------------------------------------------------------------------
PLANE1_OFFSET	equ	BYTESPERROW
PLANE2_OFFSET	equ	BYTESPERROW*2
PLANE3_OFFSET	equ	BYTESPERROW*3
PLANE4_OFFSET	equ	BYTESPERROW*4
FRAME_DEST0		equ	0
FRAME_CMD0		equ	4
FRAME_DEST1		equ	8
FRAME_CMD1		equ	12
FRAME_COUNT0	equ	16
FRAME_COUNT1	equ	18

; ---------------------------------------------------------------------------
; void DrawShadebobsFrameFastAsm(
;   __reg("a0") struct BobFrame *frame
; )
;
; Draws both shadebobs from one prepared frame entry. The frame entry already
; contains absolute destination pointers, command pointers and DBRA-ready
; command counts. This removes destination offset addition and count fixup
; from the per-frame path.
;
; struct BobFrame layout:
;   +0  UBYTE         *Dest0
;   +4  struct BobCmd *Cmd0
;   +8  UBYTE         *Dest1
;   +12 struct BobCmd *Cmd1
;   +16 UWORD         Count0  ; command count minus one
;   +18 UWORD         Count1  ; command count minus one
;
; Register map:
;   a0 = prepared frame data
;   a3 = active command list
;   a4 = bob destination base
;   a5 = destination word for current command
;   d0 = carry mask
;   d1 = old destination word
;   d2 = command byte offset
;   d5 = DBRA loop counter
; ---------------------------------------------------------------------------

_DrawShadebobsFrameFastAsm::
	movem.l	d2-d5/a3-a5,-(sp)        ; save used non-scratch registers

	move.l	FRAME_DEST0(a0),a4       ; load first bob destination base
	move.l	FRAME_CMD0(a0),a3        ; load first bob command list
	move.w	FRAME_COUNT0(a0),d5      ; load first bob DBRA count
.loop0
	move.w	(a3)+,d2                 ; d2 = byte offset from bob base
	move.w	(a3)+,d0                 ; d0 = initial carry mask
	lea	0(a4,d2.w),a5                ; a5 = destination word in bitplane 0

	move.w	(a5),d1                  ; load old bitplane 0 word
	eor.w	d0,(a5)                  ; write bitplane 0 = old XOR carry
	and.w	d1,d0                    ; carry = old AND carry

	move.w	PLANE1_OFFSET(a5),d1     ; load old bitplane 1 word
	eor.w	d0,PLANE1_OFFSET(a5)     ; write bitplane 1 = old XOR carry
	and.w	d1,d0                    ; carry = old AND carry

	move.w	PLANE2_OFFSET(a5),d1     ; load old bitplane 2 word
	eor.w	d0,PLANE2_OFFSET(a5)     ; write bitplane 2 = old XOR carry
	and.w	d1,d0                    ; carry = old AND carry

	move.w	PLANE3_OFFSET(a5),d1     ; load old bitplane 3 word
	eor.w	d0,PLANE3_OFFSET(a5)     ; write bitplane 3 = old XOR carry
	and.w	d1,d0                    ; carry = old AND carry

	eor.w	d0,PLANE4_OFFSET(a5)     ; write bitplane 4 = old XOR carry
	dbra	d5,.loop0                ; next command for first bob

	move.l	FRAME_DEST1(a0),a4       ; load second bob destination base
	move.l	FRAME_CMD1(a0),a3        ; load second bob command list
	move.w	FRAME_COUNT1(a0),d5      ; load second bob DBRA count
.loop1
	move.w	(a3)+,d2                 ; d2 = byte offset from bob base
	move.w	(a3)+,d0                 ; d0 = initial carry mask
	lea	0(a4,d2.w),a5                ; a5 = destination word in bitplane 0

	move.w	(a5),d1                  ; load old bitplane 0 word
	eor.w	d0,(a5)                  ; write bitplane 0 = old XOR carry
	and.w	d1,d0                    ; carry = old AND carry

	move.w	PLANE1_OFFSET(a5),d1     ; load old bitplane 1 word
	eor.w	d0,PLANE1_OFFSET(a5)     ; write bitplane 1 = old XOR carry
	and.w	d1,d0                    ; carry = old AND carry

	move.w	PLANE2_OFFSET(a5),d1     ; load old bitplane 2 word
	eor.w	d0,PLANE2_OFFSET(a5)     ; write bitplane 2 = old XOR carry
	and.w	d1,d0                    ; carry = old AND carry

	move.w	PLANE3_OFFSET(a5),d1     ; load old bitplane 3 word
	eor.w	d0,PLANE3_OFFSET(a5)     ; write bitplane 3 = old XOR carry
	and.w	d1,d0                    ; carry = old AND carry

	eor.w	d0,PLANE4_OFFSET(a5)     ; write bitplane 4 = old XOR carry
	dbra	d5,.loop1                ; next command for second bob

	movem.l	(sp)+,d2-d5/a3-a5        ; restore registers
	rts                              ; return
