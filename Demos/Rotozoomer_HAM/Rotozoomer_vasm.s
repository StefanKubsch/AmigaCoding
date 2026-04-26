;**********************************************************************
;* 4x4 HAM7 Rotozoomer                                                *
;*                                                                    *
;* 4 DMA bitplanes, HAM control via BPL5DAT/BPL6DAT, 52 columns      *
;* Amiga 500 OCS, 68000                                               *
;*                                                                    *
;* Combined assembler setup + hotloop for the affine sampler and     *
;* HAM planar emitter.                                               *
;**********************************************************************

    machine 68000

    include "lwmf/lwmf_hardware_regs.i"

ROTO_ROWS            equ 48
ROTO_PAIR_COUNT      equ 26
ROTO_PLANE_STRIDE    equ 26
ROTO_PLANE_BYTES     equ (ROTO_PLANE_STRIDE*ROTO_ROWS)

; -----------------------------------------------------------------------------
; Shared constants from the C side
; -----------------------------------------------------------------------------

ROTO_DELTA_STARTUC_OFFSET equ 0
ROTO_DELTA_STARTUL_OFFSET equ 2
ROTO_DELTA_STARTVTRANS_OFFSET equ 4
ROTO_DELTA_PACKED_DU   equ 6
ROTO_DELTA_PACKED_DUL  equ 10
ROTO_DELTA_PACKED_DV   equ 14

; -----------------------------------------------------------------------------
; PROCESS_PAIR
;
; Input:
; d0 = Uc = (U >> 6) in a wrapping WORD state
; d1 = ((V << 1) ^ $8000) in 16-bit wrapped form
; d2 = Ul = ((U & $003F) << 2) in the low byte
; d3 = packed Du state: high word = RowStepUc, low word = DuC
; d4 = packed low-U state: high word = RowStepUl, low word = DuL in the low byte
; d5 = packed V state: high word = RowStepVTrans, low word = DvDxTrans
; a1 = packed texture midpoint for texel 0 (high-nibble table)
; a2 = temporary signed texel-0 offset holder during the pair merge
; a3 = packed texture midpoint for texel 1 (pre-shifted low-nibble table)
; a5 = plane 0 destination byte
; a4 = plane 1 destination byte
; a6 = plane 2 destination byte
; a0 = plane 3 destination byte
;
; Notes:
; - The U path no longer rebuilds the texel address from the full 8.8 value via
;   LSR #6 + ANDI per sample.
; - Instead it keeps an exact split state:
;       U  = (Uc << 6) | (Ul >> 2)
;   with carry propagation handled by ADD.B / ADDX.W.
; - The final 4-byte texel offset is now taken directly as (Uc & $01FC).
; - RowStepUc/Ul/V live in the high words of D3/D4/D5 so the row-end update
;   no longer needs stack loads for those values.
;
; Clobbers:
; d6, d7, a2
; -----------------------------------------------------------------------------

PROCESS_PAIR macro                        ; Process two logical texels and emit one byte into each of the four data bitplanes.
    move.w  d1,d6                         ; Copy the pre-biased/scaled V value to a temporary offset register.
    andi.w  #$FE00,d6                     ; Keep the ready-made 512-byte row contribution plus midpoint bias.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d7,d6                         ; Combine row contribution and horizontal texel contribution.
    movea.w d6,a2                         ; Keep texel 0's signed texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.w   d5,d1                         ; Advance transformed V by transformed DvDx to the second texel.

    move.w  d1,d6                         ; Copy updated pre-biased/scaled V for the second texel.
    andi.w  #$FE00,d6                     ; Keep the ready-made row contribution plus midpoint bias for sample two.
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d7,d6                         ; Form the final packed-texture offset for texel two.
    move.l  (a3,d6.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.w   d5,d1                         ; Advance transformed V to the next pair's first texel.

    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
endm                                      ; End of the two-texel processing macro.

; -----------------------------------------------------------------------------
; void RenderFrameAsm(__reg("a0") UBYTE *Dest)
;
; C updates the animation phases separately. This routine pulls the shared
; tables and phases directly from global symbols, computes the per-frame
; affine setup, and then falls straight into the unrolled body renderer.
; -----------------------------------------------------------------------------

_RenderFrameAsm::                         ; Entry point called from C with plane 0 destination in A0.
    movem.l d2-d7/a1-a6,-(sp)             ; Save all registers used by the routine.

    movea.l a0,a5                         ; Keep plane 0 destination in A5.

    lea     _AngleDeltaOffsetTab,a2       ; Get the precomputed angle-to-delta byte-offset table.

    moveq   #0,d0                         ; Clear D0 before loading the angle phase byte.
    move.b  _AnglePhase,d0                ; Load the current angle phase.
    add.w   d0,d0                         ; Convert the UBYTE phase index into a WORD table byte offset.
    move.w  0(a2,d0.w),d0                 ; Fetch the precomputed angle-byte offset inside one zoom row.

    lea     _ZoomDeltaBasePtrTab,a2       ; Get the precomputed zoom-phase -> delta-row pointer table.
    moveq   #0,d7                         ; Clear D7 before loading the zoom phase byte.
    move.b  _ZoomPhase,d7                 ; Load the current zoom phase.
    add.w   d7,d7                         ; Convert the UBYTE phase index into a WORD table byte offset.
    add.w   d7,d7                         ; Convert the WORD offset into a LONG pointer-table offset.
    movea.l 0(a2,d7.w),a2                 ; Load the exact delta-row base pointer for this frame's zoom phase.

    move.w  ROTO_DELTA_STARTUC_OFFSET(a2,d0.w),d6 ; Load the precomputed split RowU coarse offset.
    move.w  ROTO_DELTA_STARTUL_OFFSET(a2,d0.w),d2 ; Load the precomputed split RowU low offset.
    move.w  ROTO_DELTA_STARTVTRANS_OFFSET(a2,d0.w),d7 ; Load the transformed RowV start offset.
    move.l  ROTO_DELTA_PACKED_DU(a2,d0.w),d3 ; Load [RowStepUc|DuC] in one longword.
    move.l  ROTO_DELTA_PACKED_DUL(a2,d0.w),d4 ; Load [RowStepUl|DuL] in one longword.
    move.l  ROTO_DELTA_PACKED_DV(a2,d0.w),d5 ; Load [RowStepVTrans|DvDxTrans] in one longword.

    lea     _MoveTabUcBase,a2             ; Get the precomputed coarse-U movement base table.
    moveq   #0,d0                         ; Clear D0 before loading MovePhaseX.
    move.b  _MovePhaseX,d0                ; Load the X movement phase.
    add.w   d0,d0                         ; Convert the WORD table index into a byte offset.
    move.w  0(a2,d0.w),d0                 ; Load the ready-made coarse U base for this movement phase.
    add.w   d6,d0                         ; Add the precomputed split RowU coarse offset.
    andi.w  #$03FF,d0                     ; Keep the wrapped 10-bit coarse-U domain produced by the original LSR.W path.

    lea     _MoveTabVTransBase,a2         ; Get the precomputed transformed-V movement base table.
    moveq   #0,d1                         ; Clear D1 before loading MovePhaseY.
    move.b  _MovePhaseY,d1                ; Load the Y movement phase.
    add.w   d1,d1                         ; Convert the WORD table index into a byte offset.
    move.w  0(a2,d1.w),d1                 ; Load the ready-made transformed RowV base.
    add.w   d7,d1                         ; Add the transformed RowV start offset.

    movea.l _TexturePackedMidHi,a1        ; Load the texel-0 packed-texture midpoint pointer.
    movea.l _TexturePackedMidLo,a3        ; Load the texel-1 pre-shifted texture base.

    move.w  #ROTO_ROWS-1,d6               ; Seed the row loop counter in the low word once.

    lea     ROTO_PLANE_BYTES(a5),a4       ; Build plane 1 base pointer from plane 0.
    lea     (ROTO_PLANE_BYTES*2)(a5),a6   ; Build plane 2 base pointer from plane 0.
    lea     (ROTO_PLANE_BYTES*3)(a5),a0   ; Build plane 3 base pointer from plane 0.

.row_loop:
    swap    d6                            ; Move the row counter into the high word so PROCESS_PAIR can reuse D6 low.
    PROCESS_PAIR
    PROCESS_PAIR
    PROCESS_PAIR
    PROCESS_PAIR
    PROCESS_PAIR
    PROCESS_PAIR
    PROCESS_PAIR
    PROCESS_PAIR
    PROCESS_PAIR
    PROCESS_PAIR
    PROCESS_PAIR
    PROCESS_PAIR
    PROCESS_PAIR
    PROCESS_PAIR
    PROCESS_PAIR
    PROCESS_PAIR
    PROCESS_PAIR
    PROCESS_PAIR
    PROCESS_PAIR
    PROCESS_PAIR
    PROCESS_PAIR
    PROCESS_PAIR
    PROCESS_PAIR
    PROCESS_PAIR
    PROCESS_PAIR
    PROCESS_PAIR

    swap    d4                            ; Bring RowStepUl into the low word without disturbing X.
    add.b   d4,d2                         ; Move the split Ul state from the end of this row to the next row start.
    swap    d4                            ; Restore DuL for the next row.
    swap    d3                            ; Bring RowStepUc into the low word while preserving X.
    addx.w  d3,d0                         ; Move the split Uc state from the end of this row to the next row start.
    swap    d3                            ; Restore DuC for the next row.
    swap    d5                            ; Bring RowStepVTrans into the low word.
    add.w   d5,d1                         ; Move transformed V from the end of this row to the next row start.
    swap    d5                            ; Restore DvDxTrans for the next row.

    swap    d6                            ; Bring the preserved row counter back into the low word.
    dbra    d6,.row_loop                   ; Repeat until all 48 rows have been rendered.

    movem.l (sp)+,d2-d7/a1-a6             ; Restore saved registers.
    rts                                    ; Return to the C caller.
