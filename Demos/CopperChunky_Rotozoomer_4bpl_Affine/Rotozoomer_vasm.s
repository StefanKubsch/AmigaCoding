; -----------------------------------------------------------------------------
; Rotozoomer drawing routine
; Amiga 500 OCS / 68000 - vasm Motorola syntax
;
; Macro-shortened variant:
; - hot loop behavior is unchanged
; - repeated 4-pixel blocks are emitted via macros
; - register usage and stack layout stay compatible with the original
; -----------------------------------------------------------------------------

	machine 68000                    ; Assemble for Motorola 68000 CPU.

	include "lwmf/lwmf_hardware_regs.i" ; Include hardware register definitions used by the project.

ROTO_ROWS             equ 48            ; Number of output rows drawn by the rotozoomer.
ROTO_GROUP_COUNT      equ 3             ; 3 iterations * 4 blocks * 4 pixels = 48 pixels per row.

; -----------------------------------------------------------------------------
; struct RotoRowPlanes
; -----------------------------------------------------------------------------
RRP_P0                equ 0             ; Offset of plane 0 pointer inside RotoRowPlanes.
RRP_P1                equ 4             ; Offset of plane 1 pointer inside RotoRowPlanes.
RRP_P2                equ 8             ; Offset of plane 2 pointer inside RotoRowPlanes.
RRP_P3                equ 12            ; Offset of plane 3 pointer inside RotoRowPlanes.
RRP_SIZE              equ 16            ; Total size of one RotoRowPlanes entry.

; -----------------------------------------------------------------------------
; struct RotoAsmParams
; Must match C exactly.
; -----------------------------------------------------------------------------
RA_Texture            equ 0             ; Pointer to texture base.
RA_RowPtr             equ 4             ; Pointer to array of row plane pointers.
RA_Expand             equ 8             ; Pointer to lookup/expansion tables.
RA_RowU               equ 12            ; Initial U coordinate for the first row (8.8 fixed point).
RA_RowV               equ 14            ; Initial V coordinate for the first row (8.8 fixed point).
RA_DuDx               equ 16            ; U delta per pixel in X direction (8.8 fixed point).
RA_DvDx               equ 18            ; V delta per pixel in X direction (8.8 fixed point).
RA_DuDy               equ 20            ; U delta per row in Y direction (8.8 fixed point).
RA_DvDy               equ 22            ; V delta per row in Y direction (8.8 fixed point).

; -----------------------------------------------------------------------------
; PairExpand layout
; -----------------------------------------------------------------------------
PE_Pair2Idx           equ 0             ; Base offset of pair-to-index lookup table.
PE_Expand4Pix         equ 131072        ; Offset of 4-pixel expansion table: 65536 * sizeof(UWORD).

; -----------------------------------------------------------------------------
; Stack locals
; -----------------------------------------------------------------------------
LOC_RowCnt            equ 0             ; Current row counter (word).
LOC_DuDy              equ 2             ; Cached DuDy value (word).
LOC_DvDy              equ 4             ; Cached DvDy value (word).
LOC_RowU              equ 6             ; Current row start U coordinate (word, 8.8).
LOC_RowV              equ 8             ; Current row start V coordinate (word, 8.8).
LOC_RowPtr            equ 10            ; Current cursor into row pointer table (long).
LOC_MapBase           equ 14            ; Saved base pointer to Pair2Idx lookup table (long).
LOC_GroupCnt          equ 18            ; Current 16-pixel group counter within a row (word).
LOC_DuFrac            equ 20            ; Fractional byte of DuDx.
LOC_DvFrac            equ 21            ; Fractional byte of DvDx.
LOC_SIZE              equ 22            ; Total local stack frame size.

; -----------------------------------------------------------------------------
; Register usage
;
; a0 = Pair2Idx base during hotloop / row cursor before that
; a1 = plane 0 destination pointer
; a2 = plane 1 destination pointer
; a3 = plane 2 destination pointer
; a4 = plane 3 destination pointer
; a5 = texture sample base (middle of 256x256 signed window)
; a6 = Expand4Pix base
;
; d0 = u_frac  (low byte used)
; d1 = u_int   (low byte used, 0..255)
; d2 = v_frac  (low byte used)
; d3 = v_int   (low byte used, 0..255)
; d4 = du_int  (low byte used)
; d5 = dv_int  (low byte used)
; d6 = pair/key/idx01/out01 scratch
; d7 = address/texel/idx23/out23 scratch
; -----------------------------------------------------------------------------

; -----------------------------------------------------------------------------
; Hotloop helper macros
; -----------------------------------------------------------------------------

	macro ADVANCE_UV                 ; Advance U and V by one pixel step in X direction.
	add.b   LOC_DuFrac(sp),d0        ; Add fractional part of DuDx to current U fraction.
	addx.b  d4,d1                    ; Add integer part of DuDx plus carry into current U integer.
	add.b   LOC_DvFrac(sp),d2        ; Add fractional part of DvDx to current V fraction.
	addx.b  d5,d3                    ; Add integer part of DvDx plus carry into current V integer.
	endm                             ; End of ADVANCE_UV macro.

	macro BUILD_ADDR_D7              ; Build 16-bit texture address from V:int in high byte and U:int in low byte.
	move.w  d3,d7                    ; Copy current V integer into d7.
	lsl.w   #8,d7                    ; Shift V integer into the high byte position.
	move.b  d1,d7                    ; Insert current U integer into the low byte.
	endm                             ; End of BUILD_ADDR_D7 macro.

	macro FETCH_TEXEL_TO_D6          ; Sample one texel into d6 and advance UV afterwards.
	BUILD_ADDR_D7                    ; Construct texture address in d7.
	move.b  (a5,d7.w),d6             ; Load signed 8-bit texel from texture.
	ext.w   d6                       ; Sign-extend texel to word.
	ADVANCE_UV                       ; Advance U/V to the next pixel position.
	endm                             ; End of FETCH_TEXEL_TO_D6 macro.

	macro FETCH_TEXEL_TO_D7          ; Sample one texel into d7 and advance UV afterwards.
	BUILD_ADDR_D7                    ; Construct texture address in d7.
	move.b  (a5,d7.w),d7             ; Load signed 8-bit texel from texture.
	ext.w   d7                       ; Sign-extend texel to word.
	ADVANCE_UV                       ; Advance U/V to the next pixel position.
	endm                             ; End of FETCH_TEXEL_TO_D7 macro.

	macro BUILD_PAIR1                ; Build the first 2-texel half of a 4-texel lookup key.
	moveq   #0,d6                    ; Clear d6 before composing the packed pair.
	FETCH_TEXEL_TO_D6                ; Fetch first texel into d6.
	FETCH_TEXEL_TO_D7                ; Fetch second texel into d7.
	lsl.w   #4,d7                    ; Shift second texel nibble into its packed position.
	or.w    d7,d6                    ; Combine first and second texel into one word.
	lsl.w   #8,d6                    ; Move the first pair into the upper byte lane for the final 4-texel key.
	endm                             ; End of BUILD_PAIR1 macro.

	macro ADD_PAIR2_TEXEL0           ; Add third texel to the packed 4-texel key.
	FETCH_TEXEL_TO_D7                ; Fetch third texel into d7.
	or.w    d7,d6                    ; Merge it into d6.
	endm                             ; End of ADD_PAIR2_TEXEL0 macro.

	macro ADD_PAIR2_TEXEL1           ; Add fourth texel to the packed 4-texel key.
	FETCH_TEXEL_TO_D7                ; Fetch fourth texel into d7.
	lsl.w   #4,d7                    ; Shift fourth texel nibble into its final position.
	or.w    d7,d6                    ; Merge it into d6, completing the packed lookup key.
	endm                             ; End of ADD_PAIR2_TEXEL1 macro.

	macro LOOKUP_AND_EXPAND          ; Convert packed texel key into 4 planar output words.
	add.l   d6,d6                    ; Multiply packed key by 2 because Pair2Idx stores words.
	move.w  0(a0,d6.l),d7            ; Load pair lookup result: d7 = [idx23 | idx01].

	moveq   #0,d6                    ; Clear d6 before extracting idx01.
	move.b  d7,d6                    ; Extract low byte = idx01.
	lsr.w   #8,d7                    ; Shift high byte down so d7 = idx23.

	add.w   d6,d6                    ; Multiply idx01 by 2.
	add.w   d6,d6                    ; Multiply idx01 by 4 because Expand4Pix entries are longs.
	move.l  (a6,d6.w),d6             ; Load expanded bits for planes 0 and 1: d6 = [plane1 | plane0].

	add.w   d7,d7                    ; Multiply idx23 by 2.
	add.w   d7,d7                    ; Multiply idx23 by 4 because Expand4Pix entries are longs.
	move.l  (a6,d7.w),d7             ; Load expanded bits for planes 2 and 3: d7 = [plane3 | plane2].
	endm                             ; End of LOOKUP_AND_EXPAND macro.

	macro WRITE_4PIX                 ; Write four expanded pixels to the four bitplane streams.
	move.w  d6,(a1)+                 ; Write plane 0 word and advance plane 0 pointer.
	swap    d6                       ; Bring plane 1 word into the low half.
	move.w  d6,(a2)+                 ; Write plane 1 word and advance plane 1 pointer.

	move.w  d7,(a3)+                 ; Write plane 2 word and advance plane 2 pointer.
	swap    d7                       ; Bring plane 3 word into the low half.
	move.w  d7,(a4)+                 ; Write plane 3 word and advance plane 3 pointer.
	endm                             ; End of WRITE_4PIX macro.

	macro EMIT_4PIX_BLOCK            ; Full pipeline for one 4-pixel output block.
	BUILD_PAIR1                      ; Build packed contribution from texels 0 and 1.
	ADD_PAIR2_TEXEL0                 ; Add texel 2 to the packed key.
	ADD_PAIR2_TEXEL1                 ; Add texel 3 to the packed key.
	LOOKUP_AND_EXPAND                ; Expand lookup result into planar output words.
	WRITE_4PIX                       ; Store the generated 4-pixel block.
	endm                             ; End of EMIT_4PIX_BLOCK macro.

_DrawRotoBodyAsm::                 ; Entry point of the assembly rotozoomer routine.
	movem.l d2-d7/a1-a6,-(sp)        ; Save all callee-saved/scratch registers used by this routine.
	lea     -LOC_SIZE(sp),sp         ; Reserve local stack frame.

	; Persistent pointers / increments.
	movea.l RA_Texture(a0),a5        ; Load texture base pointer into a5.

	movea.l RA_Expand(a0),a1         ; Load base pointer to lookup/expansion tables.
	move.l  a1,LOC_MapBase(sp)       ; Save Pair2Idx base pointer in locals.
	movea.l a1,a6                    ; Copy lookup base into a6.
	adda.l  #PE_Expand4Pix,a6        ; Advance a6 to the Expand4Pix table.

	movea.l RA_RowPtr(a0),a1         ; Load pointer to row plane pointer array.
	move.l  a1,LOC_RowPtr(sp)        ; Save current row cursor in locals.

	; DuDx / DvDx split into integer byte in regs and fraction byte in locals.
	moveq   #0,d4                    ; Clear d4 before loading DuDx integer byte.
	move.b  RA_DuDx(a0),d4           ; Load integer byte of DuDx into d4.
	move.b  RA_DuDx+1(a0),LOC_DuFrac(sp) ; Store fractional byte of DuDx in local storage.

	moveq   #0,d5                    ; Clear d5 before loading DvDx integer byte.
	move.b  RA_DvDx(a0),d5           ; Load integer byte of DvDx into d5.
	move.b  RA_DvDx+1(a0),LOC_DvFrac(sp) ; Store fractional byte of DvDx in local storage.

	; Row-to-row deltas stay as full 8.8 words.
	move.w  RA_DuDy(a0),LOC_DuDy(sp) ; Cache full DuDy fixed-point delta.
	move.w  RA_DvDy(a0),LOC_DvDy(sp) ; Cache full DvDy fixed-point delta.

	move.w  RA_RowU(a0),LOC_RowU(sp) ; Cache current row start U.
	move.w  RA_RowV(a0),LOC_RowV(sp) ; Cache current row start V.

	move.w  #ROTO_ROWS-1,LOC_RowCnt(sp) ; Initialize row loop counter for 48 rows.

.row_loop:                         ; Start of outer loop over all rows.
	tst.w   LOC_RowCnt(sp)           ; Test whether all rows are finished.
	bmi.w   .done                    ; Exit when row counter became negative.

	; Restore row cursor.
	movea.l LOC_RowPtr(sp),a0        ; Reload pointer to current row's plane pointer struct.

	; Load prepared plane pointers for this logical row.
	movem.l (a0),a1-a4               ; Load plane 0..3 destination pointers.

	; Advance row cursor once and store it away.
	lea     RRP_SIZE(a0),a0          ; Step to the next RotoRowPlanes entry.
	move.l  a0,LOC_RowPtr(sp)        ; Save updated row cursor.

	; Restore Pair2Idx base for the hotloop.
	movea.l LOC_MapBase(sp),a0       ; Reload pair lookup table base into a0.

	; Split current row start coordinates: word = [int][frac]
	moveq   #0,d0                    ; Clear d0 for U fractional part.
	moveq   #0,d1                    ; Clear d1 for U integer part.
	moveq   #0,d2                    ; Clear d2 for V fractional part.
	moveq   #0,d3                    ; Clear d3 for V integer part.

	move.b  LOC_RowU+1(sp),d0        ; Load U fractional byte.
	move.b  LOC_RowU(sp),d1          ; Load U integer byte.
	move.b  LOC_RowV+1(sp),d2        ; Load V fractional byte.
	move.b  LOC_RowV(sp),d3          ; Load V integer byte.

	move.w  #ROTO_GROUP_COUNT-1,LOC_GroupCnt(sp) ; Initialize loop counter for 3 groups of 16 pixels.

.group_loop:                       ; Start of inner loop over one 16-pixel group.
	EMIT_4PIX_BLOCK                  ; Generate pixels  0.. 3 within the current 16-pixel group.
	EMIT_4PIX_BLOCK                  ; Generate pixels  4.. 7 within the current 16-pixel group.
	EMIT_4PIX_BLOCK                  ; Generate pixels  8..11 within the current 16-pixel group.
	EMIT_4PIX_BLOCK                  ; Generate pixels 12..15 within the current 16-pixel group.

	subq.w  #1,LOC_GroupCnt(sp)      ; Decrement group counter.
	bpl.w   .group_loop              ; Continue until all 3 groups were emitted.

	; Advance row start coordinates for the next logical row.
	move.w  LOC_DuDy(sp),d7          ; Load DuDy delta.
	add.w   d7,LOC_RowU(sp)          ; Add DuDy to next row's start U.
	move.w  LOC_DvDy(sp),d7          ; Load DvDy delta.
	add.w   d7,LOC_RowV(sp)          ; Add DvDy to next row's start V.

	subq.w  #1,LOC_RowCnt(sp)        ; Decrement remaining row count.
	bra.w   .row_loop                ; Process the next row.

.done:                             ; Common exit point.
	lea     LOC_SIZE(sp),sp          ; Release local stack frame.
	movem.l (sp)+,d2-d7/a1-a6        ; Restore saved registers.
	rts                              ; Return to caller.
