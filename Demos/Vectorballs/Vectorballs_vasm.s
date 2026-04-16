; Fixed blitter routines for Vectorballs
; Amiga 500 OCS / 68000 - vasm Motorola syntax
;
; These routines are intentionally specialized for this effect and this
; exact data layout:
;
; - 48 bobs per frame
; - 16x16 pixels per bob
; - 4 interleaved bitplanes
; - pre-shifted source and mask data
; - no clipping
; - no bounds checks
; - no generic fallback path
;
; The goal here is not flexibility but low overhead on a plain A500.
;
; (C) 2026 by Stefan Kubsch / Deep4
;

	machine 68000

	include "lwmf/lwmf_hardware_regs.i"

; ---------------------------------------------------------------------------
; Vectorballs blitter constants
; ---------------------------------------------------------------------------

VB_NUM_BALLS              equ 48

; Cookie-cut minterm:
;   A = mask, B = bob source, C = destination background
;   D = (C & ~A) | (B & A)
;
; With the matching mask data, color 0 / black stays transparent across all
; bitplanes and only the visible bob pixels are written into the destination.
VB_MINTERM_COOKIE         equ $0FCA

; Clear minterm: write zero to D.
VB_MINTERM_CLEAR          equ $0100

; ---------------------------------------------------------------------------
; Fixed 16x16 bob geometry
; ---------------------------------------------------------------------------

VB_BALL_SIZE              equ 16

; Each pre-shifted 16-pixel row is stored as 2 words, because any shifted draw
; may span at most two destination words.
VB_BOB_WORDS              equ 2
VB_BOB_BYTES              equ VB_BOB_WORDS*2

; The bob data is stored in interleaved plane order:
;   row0 plane0, row0 plane1, row0 plane2, row0 plane3,
;   row1 plane0, row1 plane1, ...
;
; So the blitter height is 16 rows * 4 planes = 64 logical rows.
VB_BOB_ROWS               equ VB_BALL_SIZE*NUMBEROFBITPLANES

; BLTSIZE = (height << 6) | width-in-words
VB_BOB_BLTSIZE            equ (VB_BOB_ROWS<<6)|VB_BOB_WORDS

; Destination modulo between logical rows.
; After writing 2 words (= 4 bytes), advance to the next interleaved row.
VB_BOB_DEST_MOD           equ BYTESPERROW-VB_BOB_BYTES

; ---------------------------------------------------------------------------
; void DrawVectorBallsBlit(
;   __reg("a0") UBYTE *dstPlane0,
;   __reg("a1") const UWORD *sortedDrawOffsetPtr,
;   __reg("a2") UWORD * const *sortedMaskPtr,
;   __reg("a3") UWORD * const *sortedSourcePtr
; )
;
; Fixed cookie-cut bob path for the current Vectorballs effect.
;
; The caller builds a linear draw command stream once per frame after the
; Z-order sort. This routine then only walks the three arrays sequentially:
;
;   sortedDrawOffsetPtr[i] = byte offset from plane0 base to bob top-left word
;   sortedMaskPtr[i]       = pointer to the pre-shifted mask data for bob i
;   sortedSourcePtr[i]     = pointer to the pre-shifted source data for bob i
;
; There is no per-bob indirection through ZOrder anymore.
; No projection, no clipping and no generic bitmap handling happen here.
;
; Register map:
;   a0 = dstPlane0             (constant base pointer for the current backbuffer)
;   a1 = sortedDrawOffsetPtr   (advanced by one word per bob)
;   a2 = sortedMaskPtr         (advanced by one longword pointer per bob)
;   a3 = sortedSourcePtr       (advanced by one longword pointer per bob)
;   a5 = CUSTOMREGS            ($DFF000)
;   d0 = zero-extended destination byte offset for the current bob
;   d4 = destination chip address for the current bob
;   d5 = current mask pointer
;   d6 = current source pointer
;   d7 = loop counter for 48 bobs
; ---------------------------------------------------------------------------

_DrawVectorBallsBlit::
	; Save only the registers we actually clobber in this fixed draw path.
	movem.l	d4-d7/a2-a3/a5,-(sp)
	lea	CUSTOMREGS,a5

	; Wait for any previous blit to finish before programming the constant state
	; for this whole 48-bob batch.
.wait_draw_init:
	btst.b	#DMAB_BLITTER,(DMACONR-CUSTOMREGS,a5)
	bne.s	.wait_draw_init

	; Program the constant cookie-cut state once.
	move.w	#VB_MINTERM_COOKIE,(BLTCON0-CUSTOMREGS,a5) ; cookie-cut transparency minterm
	clr.w	(BLTCON1-CUSTOMREGS,a5)                     ; preshifted data, no shift here
	move.w	#$FFFF,(BLTAFWM-CUSTOMREGS,a5)             ; first-word mask: all bits
	move.w	#$FFFF,(BLTALWM-CUSTOMREGS,a5)             ; last-word mask:  all bits
	clr.w	(BLTAMOD-CUSTOMREGS,a5)                     ; packed mask rows
	clr.w	(BLTBMOD-CUSTOMREGS,a5)                     ; packed source rows
	move.w	#VB_BOB_DEST_MOD,(BLTCMOD-CUSTOMREGS,a5)   ; destination modulo for channel C
	move.w	#VB_BOB_DEST_MOD,(BLTDMOD-CUSTOMREGS,a5)   ; destination modulo for channel D

	moveq	#VB_NUM_BALLS-1,d7

.draw_loop:
	; Load the next destination byte offset from the already sorted command
	; stream and turn it into an absolute chip-RAM destination address.
	moveq	#0,d0
	move.w	(a1)+,d0
	move.l	a0,d4
	add.l	d0,d4

	; Load the already selected preshifted mask/source pointers for this bob.
	move.l	(a2)+,d5
	move.l	(a3)+,d6

	; IMPORTANT: wait before touching any per-blit register.
	; This routine runs one blit per bob and reprograms source/destination
	; pointers every iteration, so each new blit must wait for the previous one.
.wait_bob_blit:
	btst.b	#DMAB_BLITTER,(DMACONR-CUSTOMREGS,a5)
	bne.s	.wait_bob_blit

	; Write per-bob registers and trigger the fixed 16x16 interleaved blit.
	move.l	d5,(BLTAPTH-CUSTOMREGS,a5)                 ; A = mask data
	move.l	d6,(BLTBPTH-CUSTOMREGS,a5)                 ; B = source data
	move.l	d4,(BLTCPTH-CUSTOMREGS,a5)                 ; C = destination background
	move.l	d4,(BLTDPTH-CUSTOMREGS,a5)                 ; D = destination writeback
	move.w	#VB_BOB_BLTSIZE,(BLTSIZE-CUSTOMREGS,a5)    ; start blit (must be last)

	dbra	d7,.draw_loop

	; Wait for the last bob blit to finish before returning.
.wait_draw_last:
	btst.b	#DMAB_BLITTER,(DMACONR-CUSTOMREGS,a5)
	bne.s	.wait_draw_last

	movem.l	(sp)+,d4-d7/a2-a3/a5
	rts
