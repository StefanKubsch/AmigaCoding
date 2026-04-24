;**********************************************************************
;* 4x4 HAM7 Rotozoomer                                                *
;*                                                                    *
;* 4 DMA bitplanes, HAM control via BPL5DAT/BPL6DAT, 80 columns      *
;* Amiga 500 OCS, 68000                                               *
;*                                                                    *
;* Combined assembler setup + hotloop for the affine sampler and     *
;* HAM planar emitter.                                               *
;**********************************************************************

    machine 68000

    include "lwmf/lwmf_hardware_regs.i"

ROTO_ROWS            equ 48
ROTO_PAIR_COUNT      equ 40
ROTO_ROW_ADVANCE     equ ((BYTESPERROW*NUMBEROFBITPLANES)-ROTO_PAIR_COUNT)

; -----------------------------------------------------------------------------
; Shared constants from the C side
; -----------------------------------------------------------------------------

ROTO_CENTER_U        equ $4000
ROTO_CENTER_V        equ $4000
ROTO_ANGLE_MASK      equ $007F
ROTO_ZOOM_NUMERATOR  equ 31
ROTO_ZOOM_DENOM      equ 63
ROTO_DELTA_ROW_BYTES equ 512

; -----------------------------------------------------------------------------
; PROCESS_PAIR
;
; Input:
; d0 = U in 8.8 fixed point
; d1 = ((V << 1) ^ $8000) in 16-bit wrapped form
; a1 = packed texture midpoint (128x128, ULONG texels, base biased by +$8000)
; a5 = plane 0 destination byte
; a4 = plane 1 destination byte
; a6 = plane 2 destination byte
; a0 = plane 3 destination byte
; d4 = DuDx
; d5 = (DvDx << 1)
;
; Clobbers:
; d2, d3, d7
; -----------------------------------------------------------------------------

PROCESS_PAIR macro                        ; Process two logical texels and emit one byte into each of the four data bitplanes.
    move.w  d1,d7                         ; Copy the pre-biased/scaled V value to a temporary index register.
    andi.w  #$FE00,d7                     ; Keep the ready-made 512-byte row contribution plus midpoint bias.
    move.w  d0,d2                         ; Copy U to a temporary register.
    lsr.w   #6,d2                         ; Convert 8.8 U to a 4-byte texel offset domain.
    andi.w  #$01FC,d2                     ; Keep the aligned byte offset inside one 128-texel row.
    add.w   d2,d7                         ; Combine the biased V row contribution and U texel offset into one texture byte offset.
    move.l  (a1,d7.w),d2                  ; Fetch packed contribution for the first texel of the pair.
    add.w   d4,d0                         ; Advance U by DuDx to the second texel.
    add.w   d5,d1                         ; Advance transformed V by transformed DvDx to the second texel.

    move.w  d1,d7                         ; Copy updated pre-biased/scaled V for the second texel.
    andi.w  #$FE00,d7                     ; Keep the ready-made row contribution plus midpoint bias for sample two.
    move.w  d0,d3                         ; Copy updated U for the second texel.
    lsr.w   #6,d3                         ; Convert U into a packed-texture byte offset contribution.
    andi.w  #$01FC,d3                     ; Keep only the aligned offset inside the current texture row.
    add.w   d3,d7                         ; Form the final packed-texture offset for texel two.
    move.l  (a1,d7.w),d3                  ; Fetch packed contribution for the second texel.
    add.w   d4,d0                         ; Advance U to the next pair's first texel.
    add.w   d5,d1                         ; Advance transformed V to the next pair's first texel.

    lsr.l   #4,d3                         ; Shift texel two down so its nibbles occupy the low half of each output byte.
    or.l    d3,d2                         ; Merge texel one and texel two into final plane bytes.

    move.b  d2,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    lsr.w   #8,d2                         ; Bring plane 1 byte into the low byte position.
    move.b  d2,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    swap    d2                            ; Swap words so plane 2/3 bytes become accessible.
    move.b  d2,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.w   #8,d2                         ; Bring plane 3 byte into the low byte position.
    move.b  d2,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
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
    subq.l  #4,sp                         ; Reserve two WORD locals for RowStepU / RowStepV.

    movea.l a0,a5                         ; Keep plane 0 destination in A5.
    movea.l _TexturePackedMid,a1          ; Load the packed-texture midpoint pointer.

    lea     _SinTab256,a2                 ; Get the address of the 256-entry sine table.

    moveq   #0,d0                         ; Clear D0 before loading the angle phase byte.
    move.b  _AnglePhase,d0                ; Load the current angle phase.
    lsr.w   #1,d0                         ; Convert phase to angle-table index (phase step = 2).
    andi.w  #ROTO_ANGLE_MASK,d0           ; Clamp explicitly to the 0..127 delta-table angle range.

    moveq   #0,d1                         ; Clear D1 before loading the zoom phase byte.
    move.b  _ZoomPhase,d1                 ; Load the current zoom phase.
    move.b  0(a2,d1.w),d1                 ; Fetch SinTab256[ZoomPhase] in the 0..63 range.

    move.w  d1,d2                         ; Copy the sine value for zoom-index conversion.
    lsl.w   #5,d2                         ; Multiply by 32.
    sub.w   d1,d2                         ; Turn that into value * 31.
    moveq   #ROTO_ZOOM_DENOM,d3           ; Prepare the constant divisor 63.
    divu    d3,d2                         ; Compute ZoomIndex = (Sin * 31) / 63.

    movea.l _DeltaTab,a3                  ; Load the delta-table base pointer.
    lsl.w   #8,d2                         ; Multiply ZoomIndex by 256 first.
    add.w   d2,d2                         ; Multiply once more to get ZoomIndex * 512 bytes.
    add.w   d0,d0                         ; Multiply AngleIndex by 2.
    add.w   d0,d0                         ; Multiply AngleIndex by 4 (sizeof RotoDelta).
    add.w   d0,d2                         ; Combine zoom-row stride and angle offset.
    move.w  0(a3,d2.w),d4                 ; Load DuDx from DeltaTab[ZoomIndex][AngleIndex].
    move.w  2(a3,d2.w),d5                 ; Load DvDx from DeltaTab[ZoomIndex][AngleIndex].

    move.w  d4,d2                         ; Copy DuDx for RowStepU calculation.
    lsl.w   #4,d2                         ; Build 16 * DuDx.
    move.w  d4,d3                         ; Copy DuDx again.
    lsl.w   #6,d3                         ; Build 64 * DuDx.
    add.w   d2,d3                         ; Combine to 80 * DuDx.
    neg.w   d3                            ; Form -(80 * DuDx).
    sub.w   d5,d3                         ; Finish RowStepU = -DvDx - (80 * DuDx).
    move.w  d3,(sp)                       ; Store RowStepU in the first local WORD.

    move.w  d5,d2                         ; Copy DvDx for RowStepV calculation.
    lsl.w   #4,d2                         ; Build 16 * DvDx.
    move.w  d5,d7                         ; Copy DvDx again.
    lsl.w   #6,d7                         ; Build 64 * DvDx.
    add.w   d2,d7                         ; Combine to 80 * DvDx.
    neg.w   d7                            ; Form -(80 * DvDx).
    add.w   d4,d7                         ; Finish the undoubled term DuDx - (80 * DvDx).
    add.w   d7,d7                         ; Convert to transformed RowStepV = 2 * (DuDx - 80 * DvDx).
    move.w  d7,2(sp)                      ; Store RowStepV in the second local WORD.

    lea     _MoveTab,a2                   ; Get the address of the 256-entry movement table.

    move.w  #ROTO_CENTER_U,d0             ; Start RowU at the texture center (64 << 8).
    moveq   #0,d2                         ; Clear D2 before loading MovePhaseX.
    move.b  _MovePhaseX,d2                ; Load the X movement phase.
    add.w   d2,d2                         ; Convert the WORD table index into a byte offset.
    add.w   0(a2,d2.w),d0                 ; Add MoveTab[MovePhaseX].
    move.w  d4,d2                         ; Copy DuDx for the 40 * DuDx term.
    lsl.w   #3,d2                         ; Build 8 * DuDx.
    move.w  d4,d3                         ; Copy DuDx again.
    lsl.w   #5,d3                         ; Build 32 * DuDx.
    add.w   d2,d3                         ; Combine to 40 * DuDx.
    sub.w   d3,d0                         ; Subtract the half-width contribution.
    move.w  d5,d2                         ; Copy DvDx for the 24 * DvDx term.
    lsl.w   #3,d2                         ; Build 8 * DvDx.
    move.w  d5,d3                         ; Copy DvDx again.
    lsl.w   #4,d3                         ; Build 16 * DvDx.
    add.w   d2,d3                         ; Combine to 24 * DvDx.
    add.w   d3,d0                         ; Add the half-height contribution from DuDy = -DvDx.

    move.w  #ROTO_CENTER_V,d1             ; Start RowV at the texture center (64 << 8).
    moveq   #0,d2                         ; Clear D2 before loading MovePhaseY.
    move.b  _MovePhaseY,d2                ; Load the Y movement phase.
    add.w   d2,d2                         ; Convert the WORD table index into a byte offset.
    add.w   0(a2,d2.w),d1                 ; Add MoveTab[MovePhaseY].
    move.w  d5,d2                         ; Copy DvDx for the 40 * DvDx term.
    lsl.w   #3,d2                         ; Build 8 * DvDx.
    move.w  d5,d3                         ; Copy DvDx again.
    lsl.w   #5,d3                         ; Build 32 * DvDx.
    add.w   d2,d3                         ; Combine to 40 * DvDx.
    sub.w   d3,d1                         ; Subtract the half-width contribution.
    move.w  d4,d2                         ; Copy DuDx for the 24 * DvDy term.
    lsl.w   #3,d2                         ; Build 8 * DuDx.
    move.w  d4,d3                         ; Copy DuDx again.
    lsl.w   #4,d3                         ; Build 16 * DuDx.
    add.w   d2,d3                         ; Combine to 24 * DuDx.
    sub.w   d3,d1                         ; Subtract the half-height contribution from DvDy = DuDx.
    add.w   d1,d1                         ; Encode V for the transformed sampler representation.
    eori.w  #$8000,d1                     ; Add the midpoint bias used by the texture address generator.

    add.w   d5,d5                         ; Convert DvDx into the transformed horizontal V delta (DvDx << 1).
    moveq   #ROTO_ROWS-1,d6               ; Set DBRA loop counter for all 48 rows.

    lea     BYTESPERROW(a5),a4            ; Build plane 1 base pointer from plane 0.
    lea     (BYTESPERROW*2)(a5),a6        ; Build plane 2 base pointer from plane 0.
    lea     (BYTESPERROW*3)(a5),a0        ; Build plane 3 base pointer from plane 0.

.row_loop:
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

    add.w   (sp),d0                       ; Move U from the end of this row to the start of the next row.
    add.w   2(sp),d1                      ; Move transformed V from the end of this row to the start of the next row.
    adda.w  #ROTO_ROW_ADVANCE,a5          ; Advance plane 0 pointer to the next logical row start.
    adda.w  #ROTO_ROW_ADVANCE,a4          ; Advance plane 1 pointer to the next logical row start.
    adda.w  #ROTO_ROW_ADVANCE,a6          ; Advance plane 2 pointer to the next logical row start.
    adda.w  #ROTO_ROW_ADVANCE,a0          ; Advance plane 3 pointer to the next logical row start.

    dbra    d6,.row_loop                  ; Repeat until all rows have been rendered.

    addq.l  #4,sp                         ; Release the two local WORDs.
    movem.l (sp)+,d2-d7/a1-a6             ; Restore saved registers.
    rts                                   ; Return to the C caller.
