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

ROTO_DELTA_PACKED_V          equ 0
ROTO_DELTA_PACKED_START      equ 4
ROTO_DELTA_PACKED_U          equ 8

; -----------------------------------------------------------------------------
; PROCESS_PAIR
;
; Input:
; d0 = Uc = (U >> 6) in a wrapping WORD state
; d1 = ((V << 1) ^ $8000) in 16-bit wrapped form
; d2 = Ul = ((U & $003F) << 2) in the low byte
; d3 = packed Du state: high word = RowStepUc, low word = DuC
; d4 = packed low-U state: high word = RowStepUl, low word = DuL in the low byte
; d5 = packed V/mask state: high word = RowStepVTrans, low word = $FE00 row mask
; d6 = inside the row body: low word = DvDxTrans, high word = preserved row counter
; a1 = packed texture midpoint for texel 0 (high-nibble table)
; a2 = temporary signed texel-0 offset holder during the pair merge
; a3 = packed texture midpoint for texel 1 (pre-shifted low-nibble table)
; a5 = plane 0 destination byte
; a4 = plane 1 destination byte
; a6 = plane 2 destination byte
; a0 = temporary signed texel-1 offset holder during the second fetch
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
    move.w  d1,d7                         ; Copy transformed V so the row contribution can be derived with the register mask.
    and.w   d5,d7                         ; Keep the ready-made 512-byte row contribution plus midpoint bias.
    movea.w d7,a2                         ; Start building texel 0's signed texture offset in A2.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed texture offset.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.w   d6,d1                         ; Advance transformed V by transformed DvDx to the second texel.

    move.w  d1,d7                         ; Copy updated transformed V for the second texel.
    and.w   d5,d7                         ; Keep the ready-made row contribution plus midpoint bias for sample two.
    movea.w d7,a0                         ; Start building texel 1's signed texture offset in A0.
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    adda.w  d7,a0                         ; Form the final packed-texture offset for texel two.
    move.l  (a3,a0.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.w   d6,d1                         ; Advance transformed V to the next pair's first texel.

    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,((ROTO_PLANE_BYTES*3)-1)(a5) ; Write plane 3 byte relative to the post-incremented plane-0 pointer.
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
    movem.l d2-d7/a2-a6,-(sp)             ; Save only the callee-saved registers that are actually preserved.

    movea.l a0,a5                         ; Keep plane 0 destination in A5.

    moveq   #0,d0                         ; Clear D0 before loading the angle phase byte.
    move.b  _AnglePhase,d0                ; Load the current angle phase.
    move.w  d0,d7                         ; Keep the even angle phase so the 12-byte entry offset can be formed.
    add.w   d0,d0                         ; Build 2 * phase.
    add.w   d7,d0                         ; Build 3 * phase.
    add.w   d0,d0                         ; Convert the even phase directly into AngleIndex * 12 bytes.

    lea     _ZoomDeltaRowOffsetTab,a2     ; Get the precomputed zoom-phase -> signed delta-row offset table.
    moveq   #0,d7                         ; Clear D7 before loading the zoom phase byte.
    move.b  _ZoomPhase,d7                 ; Load the current zoom phase.
    add.w   d7,d7                         ; Convert the UBYTE phase index into a WORD table byte offset.
    move.w  0(a2,d7.w),d7                 ; Fetch the signed row offset relative to DeltaTabMid.
    movea.l _DeltaTabMid,a2               ; Load the midpoint base of the compact delta table.
    adda.w  d7,a2                         ; Build the exact zoom-row base pointer for this frame.

    move.l  ROTO_DELTA_PACKED_V(a2,d0.w),d5 ; Load [RowStepVTrans|DvDxTrans] directly.
    move.l  ROTO_DELTA_PACKED_START(a2,d0.w),d6 ; Load [StartVTransOffset|StartUcOffset].
    move.l  ROTO_DELTA_PACKED_U(a2,d0.w),d7 ; Load the compact U-split pack.

    move.w  d6,d0                         ; Keep StartUcOffset in D0 until the coarse-U base is added.
    swap    d6                            ; Bring StartVTransOffset into the low word for the V setup path.

    move.w  d7,d4                         ; Copy the low-word small-U pack.
    swap    d7                            ; Bring [RowStepUcBias10|StartUl6] into the low word.
    move.w  d7,d2                         ; Copy the high-word U pack so StartUl can be extracted.
    andi.w  #$003F,d2                     ; Keep StartUl in the low 6 bits.
    add.w   d2,d2                         ; Restore the original <<2 encoding.
    add.w   d2,d2                         ; Finish restoring StartUlOffset.

    move.w  d7,d3                         ; Copy the high-word U pack for RowStepUc extraction.
    lsr.w   #6,d3                         ; Keep the biased 10-bit RowStepUc value.
    subi.w  #512,d3                       ; Convert the bias-encoded value back to a signed WORD.

    move.w  d4,d7                         ; Copy the low-word small-U pack for DuC extraction.
    andi.w  #$000F,d7                     ; Keep the 4-bit biased DuC value.
    subi.w  #8,d7                         ; Convert the nibble back to the signed DuC WORD.
    swap    d3                            ; Put RowStepUc into the high word of D3.
    move.w  d7,d3                         ; Install DuC in the low word of D3.

    lsr.w   #4,d4                         ; Drop the DuC nibble, leaving [RowStepUl6|DuL6].
    move.w  d4,d7                         ; Copy the remaining small-U pack for DuL extraction.
    andi.w  #$003F,d7                     ; Keep DuL in the low 6 bits.
    add.w   d7,d7                         ; Restore the original <<2 encoding.
    add.w   d7,d7                         ; Finish restoring DuL.

    lsr.w   #6,d4                         ; Keep the 6-bit RowStepUl value.
    add.w   d4,d4                         ; Restore the original <<2 encoding.
    add.w   d4,d4                         ; Finish restoring RowStepUl.
    swap    d4                            ; Put RowStepUl into the high word of D4.
    move.w  d7,d4                         ; Install DuL in the low word of D4.

    lea     _MoveTabUcBase,a2             ; Get the precomputed coarse-U movement base table.
    moveq   #0,d7                         ; Clear D7 before loading MovePhaseX.
    move.b  _MovePhaseX,d7                ; Load the X movement phase.
    add.w   d7,d7                         ; Convert the WORD table index into a byte offset.
    move.w  0(a2,d7.w),d7                 ; Load the ready-made coarse U base for this movement phase.
    add.w   d7,d0                         ; Add the precomputed split RowU coarse offset.
    andi.w  #$03FF,d0                     ; Keep the wrapped 10-bit coarse-U domain produced by the original LSR.W path.

    lea     _MoveTabVTransBase,a2         ; Get the precomputed transformed-V movement base table.
    moveq   #0,d1                         ; Clear D1 before loading MovePhaseY.
    move.b  _MovePhaseY,d1                ; Load the Y movement phase.
    add.w   d1,d1                         ; Convert the WORD table index into a byte offset.
    move.w  0(a2,d1.w),d1                 ; Load the ready-made transformed RowV base.
    add.w   d6,d1                         ; Add the transformed RowV start offset.

    movea.l _TexturePackedMidHi,a1        ; Load the texel-0 packed-texture midpoint pointer.
    movea.l _TexturePackedMidLo,a3        ; Load the texel-1 pre-shifted texture base.

    lea     ROTO_PLANE_BYTES(a5),a4       ; Build plane 1 base pointer from plane 0.
    lea     (ROTO_PLANE_BYTES*2)(a5),a6   ; Build plane 2 base pointer from plane 0.
    lea     (ROTO_PLANE_BYTES*3)(a5),a0   ; Build plane 3 base pointer once for the exact fast-path families.

    move.w  d5,d7                         ; Copy transformed DvDx so the exact cached-row family can be selected once.
    asr.w   #1,d7                         ; Convert transformed DvDx back into W-space for the cached-row updater.
    move.w  d7,d6                         ; Copy DvDx so the absolute-magnitude check does not destroy the signed original.
    bpl.s   .dv_abs_ready                 ; Positive DvDx already is its absolute magnitude.
    neg.w   d6                            ; Turn negative DvDx into its absolute magnitude for the exact-family threshold test.
.dv_abs_ready:
    cmpi.w  #511,d6                       ; The exact cached-row families stay correct while |DvDx| <= 511 in W-space.
    bhi.w   .generic_init                 ; Larger steps would need more than two row quanta per sample.

    tst.w   d7                            ; Signed DvDx decides which guaranteed-row family is exact.
    bmi.s   .dv_neg_dispatch              ; Negative steps use the -1/-2 row families.
    cmpi.w  #255,d7                       ; 0..255 rows only advance on carry from the low-byte remainder.
    bhi.w   .fast_bp1_init                ; 256..511 always advance at least one row per sample.
    bra.w   .fast_b0_init                 ; 0..255 stay in the zero-guaranteed-row family.
.dv_neg_dispatch:
    cmpi.w  #-256,d7                      ; -256..-1 always move up by at least one row per sample.
    blt.w   .fast_bm2_init                ; -511..-257 always move up by at least two rows per sample.
    bra.w   .fast_bm1_init                ; -256..-1 use the single guaranteed row-decrement family.

.fast_b0_init:
    move.w  d1,d6                         ; Copy transformed V so the cached W low byte can be recovered.
    lsr.w   #1,d6                         ; W = (transformed V >> 1), low byte used by the cached-row updater.
    andi.w  #$00FF,d6                     ; Keep only the cached W low byte in D6; the row contribution now lives in D1.
    andi.w  #$FE00,d1                     ; Cache the current 512-byte packed-texture row contribution directly in D1.
    swap    d5                            ; Bring transformed RowStepV into the low word temporarily.
    asr.w   #1,d5                         ; Convert transformed RowStepV back into the W-space row step.
    swap    d5                            ; Keep RowStepV in the high word of the fast packed-V helper.
    move.b  d7,d5                         ; Keep only DvDx's low-byte remainder in the low byte for the cached-row updater.
    swap    d6                            ; Park the cached W low byte in the high word until the fast row loop starts.
    move.w  #ROTO_ROWS-1,d6               ; Seed the fast-path row counter in the low word once.
    bra.w   .fast_b0_loop                 ; Enter the exact 0..255 cached-row loop.

.fast_bp1_init:
    move.w  d1,d6                         ; Copy transformed V so the cached W low byte can be recovered.
    lsr.w   #1,d6                         ; W = (transformed V >> 1), low byte used by the cached-row updater.
    andi.w  #$00FF,d6                     ; Keep only the cached W low byte in D6; the row contribution now lives in D1.
    andi.w  #$FE00,d1                     ; Cache the current 512-byte packed-texture row contribution directly in D1.
    swap    d5                            ; Bring transformed RowStepV into the low word temporarily.
    asr.w   #1,d5                         ; Convert transformed RowStepV back into the W-space row step.
    swap    d5                            ; Keep RowStepV in the high word of the fast packed-V helper.
    move.b  d7,d5                         ; Keep only DvDx's low-byte remainder in the low byte for the cached-row updater.
    swap    d6                            ; Park the cached W low byte in the high word until the fast row loop starts.
    move.w  #ROTO_ROWS-1,d6               ; Seed the fast-path row counter in the low word once.
    bra.w   .fast_bp1_loop                ; Enter the exact 256..511 cached-row loop.

.fast_bm1_init:
    move.w  d1,d6                         ; Copy transformed V so the cached W low byte can be recovered.
    lsr.w   #1,d6                         ; W = (transformed V >> 1), low byte used by the cached-row updater.
    andi.w  #$00FF,d6                     ; Keep only the cached W low byte in D6; the row contribution now lives in D1.
    andi.w  #$FE00,d1                     ; Cache the current 512-byte packed-texture row contribution directly in D1.
    swap    d5                            ; Bring transformed RowStepV into the low word temporarily.
    asr.w   #1,d5                         ; Convert transformed RowStepV back into the W-space row step.
    swap    d5                            ; Keep RowStepV in the high word of the fast packed-V helper.
    move.b  d7,d5                         ; Keep the wrapped positive remainder in the low byte for the cached-row updater.
    swap    d6                            ; Park the cached W low byte in the high word until the fast row loop starts.
    move.w  #ROTO_ROWS-1,d6               ; Seed the fast-path row counter in the low word once.
    bra.w   .fast_bm1_loop                ; Enter the exact -256..-1 cached-row loop.

.fast_bm2_init:
    move.w  d1,d6                         ; Copy transformed V so the cached W low byte can be recovered.
    lsr.w   #1,d6                         ; W = (transformed V >> 1), low byte used by the cached-row updater.
    andi.w  #$00FF,d6                     ; Keep only the cached W low byte in D6; the row contribution now lives in D1.
    andi.w  #$FE00,d1                     ; Cache the current 512-byte packed-texture row contribution directly in D1.
    swap    d5                            ; Bring transformed RowStepV into the low word temporarily.
    asr.w   #1,d5                         ; Convert transformed RowStepV back into the W-space row step.
    swap    d5                            ; Keep RowStepV in the high word of the fast packed-V helper.
    move.b  d7,d5                         ; Keep the wrapped positive remainder in the low byte for the cached-row updater.
    swap    d6                            ; Park the cached W low byte in the high word until the fast row loop starts.
    move.w  #ROTO_ROWS-1,d6               ; Seed the fast-path row counter in the low word once.
    bra.w   .fast_bm2_loop                ; Enter the exact -511..-257 cached-row loop.

.generic_init:
    move.w  d5,d6                         ; Copy DvDxTrans into D6 low before D5 low is repurposed as a row mask.
    move.w  #$FE00,d5                     ; Replace PackedDv low with the register mask used by both V row extracts.
    swap    d6                            ; Move DvDxTrans into the high word temporarily.
    move.w  #ROTO_ROWS-1,d6               ; Seed the row loop counter in the low word while keeping DvDxTrans in the high word.

.row_loop:
    swap    d6                            ; Bring DvDxTrans into the low word and park the row counter in the high word.
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
    swap    d5                            ; Restore the $FE00 row mask for the next row.

    swap    d6                            ; Bring the preserved row counter back into the low word and park DvDxTrans in the high word.
    dbra    d6,.row_loop                  ; Repeat until all 48 rows have been rendered.
    bra.w   .render_done                  ; Skip the exact fast-path bodies once the generic loop finishes.

.fast_b0_loop:
    swap    d6                            ; Bring the cached W low byte back into D6 low and park the row counter in D6 high.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_01                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_01:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_01                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_01:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_02                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_02:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_02                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_02:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_03                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_03:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_03                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_03:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_04                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_04:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_04                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_04:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_05                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_05:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_05                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_05:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_06                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_06:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_06                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_06:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_07                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_07:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_07                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_07:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_08                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_08:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_08                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_08:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_09                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_09:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_09                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_09:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_10                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_10:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_10                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_10:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_11                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_11:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_11                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_11:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_12                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_12:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_12                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_12:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_13                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_13:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_13                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_13:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_14                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_14:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_14                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_14:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_15                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_15:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_15                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_15:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_16                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_16:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_16                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_16:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_17                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_17:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_17                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_17:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_18                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_18:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_18                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_18:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_19                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_19:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_19                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_19:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_20                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_20:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_20                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_20:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_21                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_21:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_21                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_21:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_22                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_22:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_22                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_22:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_23                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_23:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_23                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_23:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_24                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_24:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_24                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_24:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_25                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_25:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_25                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_25:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vb01_26                    ; No carry means the cached packed-texture row stays on the same 512-byte line.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb01_26:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vb02_26                    ; No carry keeps the cached packed-texture row unchanged for the next sample.
    addi.w  #$0200,d1                     ; Carry means the cached packed-texture row moves down by one texture row.
.vb02_26:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.

    swap    d4                            ; Bring RowStepUl into the low word without disturbing X.
    add.b   d4,d2                         ; Move the split Ul state from the end of this row to the next row start.
    swap    d4                            ; Restore DuL for the next row.
    swap    d3                            ; Bring RowStepUc into the low word while preserving X.
    addx.w  d3,d0                         ; Move the split Uc state from the end of this row to the next row start.
    swap    d3                            ; Restore DuC for the next row.
    swap    d5                            ; Bring RowStepV in W-space into the low word for the once-per-row state rebuild.
    move.w  d1,d7                         ; Copy the cached actual row contribution for reconstruction of the full W state.
    lsr.w   #1,d7                         ; Convert actual row bytes back into the packed W row-half domain.
    move.b  d6,d7                         ; Reinsert the cached W low byte so D7 low becomes the exact current W state.
    add.w   d5,d7                         ; Apply RowStepV once per row in W-space.
    move.b  d7,d6                         ; Keep only the updated W low byte in D6; the row counter stays parked in D6 high.
    clr.b   d7                            ; Keep only the new W high byte contribution.
    add.w   d7,d7                         ; Convert it back into the actual 512-byte packed-texture row contribution.
    move.w  d7,d1                         ; Cache the rebuilt packed-texture row contribution for the next row.
    swap    d5                            ; Restore the fast packed-V helper format [RowStepV|DvRem].
    swap    d6                            ; Bring the preserved fast-path row counter back into the low word.
    dbra    d6,.fast_b0_loop             ; Repeat until all 48 rows have been rendered.
    bra.w   .render_done                  ; Skip the remaining loop families once this exact fast path finishes.

.fast_bp1_loop:
    swap    d6                            ; Bring the cached W low byte back into D6 low and park the row counter in D6 high.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_01                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_01:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_01                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_01:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_02                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_02:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_02                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_02:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_03                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_03:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_03                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_03:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_04                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_04:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_04                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_04:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_05                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_05:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_05                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_05:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_06                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_06:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_06                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_06:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_07                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_07:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_07                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_07:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_08                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_08:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_08                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_08:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_09                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_09:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_09                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_09:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_10                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_10:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_10                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_10:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_11                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_11:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_11                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_11:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_12                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_12:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_12                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_12:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_13                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_13:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_13                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_13:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_14                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_14:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_14                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_14:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_15                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_15:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_15                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_15:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_16                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_16:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_16                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_16:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_17                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_17:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_17                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_17:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_18                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_18:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_18                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_18:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_19                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_19:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_19                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_19:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_20                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_20:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_20                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_20:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_21                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_21:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_21                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_21:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_22                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_22:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_22                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_22:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_23                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_23:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_23                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_23:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_24                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_24:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_24                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_24:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_25                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_25:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_25                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_25:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    addi.w  #$0200,d1                     ; Large positive V steps always move down by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the horizontal V remainder.
    bcc.s   .vbp11_26                    ; No carry means the guaranteed +1 row move was sufficient this sample.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp11_26:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    addi.w  #$0200,d1                     ; Large positive V steps always advance at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbp12_26                    ; No carry means the guaranteed +1 row move was enough for sample two.
    addi.w  #$0200,d1                     ; Carry adds the optional second cached texture-row advance.
.vbp12_26:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.

    swap    d4                            ; Bring RowStepUl into the low word without disturbing X.
    add.b   d4,d2                         ; Move the split Ul state from the end of this row to the next row start.
    swap    d4                            ; Restore DuL for the next row.
    swap    d3                            ; Bring RowStepUc into the low word while preserving X.
    addx.w  d3,d0                         ; Move the split Uc state from the end of this row to the next row start.
    swap    d3                            ; Restore DuC for the next row.
    swap    d5                            ; Bring RowStepV in W-space into the low word for the once-per-row state rebuild.
    move.w  d1,d7                         ; Copy the cached actual row contribution for reconstruction of the full W state.
    lsr.w   #1,d7                         ; Convert actual row bytes back into the packed W row-half domain.
    move.b  d6,d7                         ; Reinsert the cached W low byte so D7 low becomes the exact current W state.
    add.w   d5,d7                         ; Apply RowStepV once per row in W-space.
    move.b  d7,d6                         ; Keep only the updated W low byte in D6; the row counter stays parked in D6 high.
    clr.b   d7                            ; Keep only the new W high byte contribution.
    add.w   d7,d7                         ; Convert it back into the actual 512-byte packed-texture row contribution.
    move.w  d7,d1                         ; Cache the rebuilt packed-texture row contribution for the next row.
    swap    d5                            ; Restore the fast packed-V helper format [RowStepV|DvRem].
    swap    d6                            ; Bring the preserved fast-path row counter back into the low word.
    dbra    d6,.fast_bp1_loop             ; Repeat until all 48 rows have been rendered.
    bra.w   .render_done                  ; Skip the remaining loop families once this exact fast path finishes.

.fast_bm1_loop:
    swap    d6                            ; Bring the cached W low byte back into D6 low and park the row counter in D6 high.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_01                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_01:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_01                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_01:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_02                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_02:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_02                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_02:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_03                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_03:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_03                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_03:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_04                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_04:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_04                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_04:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_05                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_05:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_05                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_05:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_06                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_06:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_06                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_06:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_07                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_07:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_07                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_07:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_08                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_08:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_08                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_08:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_09                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_09:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_09                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_09:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_10                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_10:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_10                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_10:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_11                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_11:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_11                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_11:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_12                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_12:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_12                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_12:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_13                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_13:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_13                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_13:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_14                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_14:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_14                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_14:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_15                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_15:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_15                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_15:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_16                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_16:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_16                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_16:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_17                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_17:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_17                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_17:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_18                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_18:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_18                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_18:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_19                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_19:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_19                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_19:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_20                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_20:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_20                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_20:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_21                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_21:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_21                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_21:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_22                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_22:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_22                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_22:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_23                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_23:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_23                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_23:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_24                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_24:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_24                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_24:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_25                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_25:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_25                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_25:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm11_26                    ; No carry keeps the guaranteed -1 row move for this sample.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm11_26:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Negative V steps up to one row always move up by one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm12_26                    ; No carry keeps the guaranteed -1 row move for sample two.
    addi.w  #$0200,d1                     ; Carry cancels that guaranteed row decrement, giving a net zero row move.
.vbm12_26:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.

    swap    d4                            ; Bring RowStepUl into the low word without disturbing X.
    add.b   d4,d2                         ; Move the split Ul state from the end of this row to the next row start.
    swap    d4                            ; Restore DuL for the next row.
    swap    d3                            ; Bring RowStepUc into the low word while preserving X.
    addx.w  d3,d0                         ; Move the split Uc state from the end of this row to the next row start.
    swap    d3                            ; Restore DuC for the next row.
    swap    d5                            ; Bring RowStepV in W-space into the low word for the once-per-row state rebuild.
    move.w  d1,d7                         ; Copy the cached actual row contribution for reconstruction of the full W state.
    lsr.w   #1,d7                         ; Convert actual row bytes back into the packed W row-half domain.
    move.b  d6,d7                         ; Reinsert the cached W low byte so D7 low becomes the exact current W state.
    add.w   d5,d7                         ; Apply RowStepV once per row in W-space.
    move.b  d7,d6                         ; Keep only the updated W low byte in D6; the row counter stays parked in D6 high.
    clr.b   d7                            ; Keep only the new W high byte contribution.
    add.w   d7,d7                         ; Convert it back into the actual 512-byte packed-texture row contribution.
    move.w  d7,d1                         ; Cache the rebuilt packed-texture row contribution for the next row.
    swap    d5                            ; Restore the fast packed-V helper format [RowStepV|DvRem].
    swap    d6                            ; Bring the preserved fast-path row counter back into the low word.
    dbra    d6,.fast_bm1_loop             ; Repeat until all 48 rows have been rendered.
    bra.w   .render_done                  ; Skip the remaining loop families once this exact fast path finishes.

.fast_bm2_loop:
    swap    d6                            ; Bring the cached W low byte back into D6 low and park the row counter in D6 high.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_01                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_01:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_01                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_01:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_02                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_02:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_02                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_02:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_03                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_03:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_03                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_03:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_04                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_04:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_04                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_04:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_05                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_05:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_05                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_05:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_06                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_06:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_06                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_06:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_07                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_07:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_07                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_07:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_08                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_08:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_08                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_08:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_09                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_09:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_09                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_09:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_10                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_10:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_10                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_10:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_11                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_11:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_11                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_11:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_12                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_12:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_12                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_12:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_13                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_13:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_13                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_13:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_14                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_14:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_14                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_14:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_15                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_15:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_15                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_15:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_16                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_16:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_16                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_16:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_17                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_17:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_17                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_17:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_18                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_18:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_18                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_18:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_19                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_19:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_19                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_19:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_20                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_20:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_20                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_20:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_21                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_21:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_21                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_21:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_22                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_22:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_22                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_22:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_23                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_23:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_23                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_23:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_24                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_24:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_24                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_24:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_25                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_25:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_25                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_25:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    movea.w d1,a2                         ; Seed texel 0's packed-texture row contribution directly from the cached V row.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    adda.w  d7,a2                         ; Finish texel 0's signed packed-texture offset in A2 for the final memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcc.s   .vbm21_26                    ; No carry keeps the guaranteed -2 row move for this sample.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm21_26:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0400,d1                     ; Large negative V steps always move up by at least two cached texture rows.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcc.s   .vbm22_26                    ; No carry keeps the guaranteed -2 row move for sample two.
    addi.w  #$0200,d1                     ; Carry adds one row back, so the net move becomes exactly -1 row.
.vbm22_26:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+ ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.

    swap    d4                            ; Bring RowStepUl into the low word without disturbing X.
    add.b   d4,d2                         ; Move the split Ul state from the end of this row to the next row start.
    swap    d4                            ; Restore DuL for the next row.
    swap    d3                            ; Bring RowStepUc into the low word while preserving X.
    addx.w  d3,d0                         ; Move the split Uc state from the end of this row to the next row start.
    swap    d3                            ; Restore DuC for the next row.
    swap    d5                            ; Bring RowStepV in W-space into the low word for the once-per-row state rebuild.
    move.w  d1,d7                         ; Copy the cached actual row contribution for reconstruction of the full W state.
    lsr.w   #1,d7                         ; Convert actual row bytes back into the packed W row-half domain.
    move.b  d6,d7                         ; Reinsert the cached W low byte so D7 low becomes the exact current W state.
    add.w   d5,d7                         ; Apply RowStepV once per row in W-space.
    move.b  d7,d6                         ; Keep only the updated W low byte in D6; the row counter stays parked in D6 high.
    clr.b   d7                            ; Keep only the new W high byte contribution.
    add.w   d7,d7                         ; Convert it back into the actual 512-byte packed-texture row contribution.
    move.w  d7,d1                         ; Cache the rebuilt packed-texture row contribution for the next row.
    swap    d5                            ; Restore the fast packed-V helper format [RowStepV|DvRem].
    swap    d6                            ; Bring the preserved fast-path row counter back into the low word.
    dbra    d6,.fast_bm2_loop             ; Repeat until all 48 rows have been rendered.
    bra.w   .render_done                  ; Skip the remaining loop families once this exact fast path finishes.

.render_done:

    movem.l (sp)+,d2-d7/a2-a6             ; Restore saved callee-saved registers.
    rts                                    ; Return to the C caller.
