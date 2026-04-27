;**********************************************************************
;* 4x4 HAM7 Rotozoomer                                                *
;*                                                                    *
;* 4 DMA bitplanes, HAM control via BPL5DAT/BPL6DAT, 28 columns      *
;* Amiga 500 OCS, 68000                                               *
;*                                                                    *
;* Combined assembler setup + hotloop for the affine sampler and     *
;* HAM planar emitter.                                               *
;**********************************************************************

    machine 68000

    xdef _RenderFrameAsm
    xdef _RenderFastB0Entry
    xdef _RenderFastBp1Entry
    xdef _RenderFastBm1Entry
    xdef _RenderFastBm2Entry

    include "lwmf/lwmf_hardware_regs.i"

ROTO_ROWS            equ 48
ROTO_PAIR_COUNT      equ 14
ROTO_PLANE_STRIDE    equ 14
ROTO_PLANE_BYTES     equ (ROTO_PLANE_STRIDE*ROTO_ROWS)

; -----------------------------------------------------------------------------
; Shared constants from the C side
; -----------------------------------------------------------------------------

ROTO_FRAME_DUC               equ 0
ROTO_FRAME_DUL               equ 2
ROTO_FRAME_DVREM             equ 3
ROTO_FRAME_ENTRY             equ 4
ROTO_FRAME_ROWS              equ 8
ROTO_FRAME_SIZE              equ 872

ROTO_ROW_START_UC          equ 0
ROTO_ROW_START_ROW         equ 2
ROTO_ROW_PACKED_BYTES      equ 4
ROTO_ROW_START_PAIR_PACKED equ 6
ROTO_ROW_SIZE              equ 18

; -----------------------------------------------------------------------------
; PROCESS_PAIR
;
; Input:
; d0 = Uc = (U >> 6) in a wrapping WORD state
; d1 = cached packed-texture row contribution for the current sample
; d2 = Ul = ((U & $003F) << 2) in the low byte
; d3 = DuC in the low word
; d4 = DuL in the low byte
; d5 = DvDx remainder in the low byte
; d6 = inside the row body: high word = remaining row counter, low byte = cached W low byte
; a1 = packed texture midpoint for texel 0 (high-nibble table)
; a2 = temporary signed texel-0 offset holder during the pair merge
; a3 = packed texture midpoint for texel 1 (pre-shifted low-nibble table)
; a5 = plane 0 destination byte
; a4 = plane 1 destination byte
; a6 = plane 2 destination byte
; a0 = current row-state stream pointer between row starts
;
; Notes:
; - The U path no longer rebuilds the texel address from the full 8.8 value via
;   LSR #6 + ANDI per sample.
; - Instead it keeps an exact split state:
;       U  = (Uc << 6) | (Ul >> 2)
;   with carry propagation handled by ADD.B / ADDX.W.
; - The final 4-byte texel offset is now taken directly as (Uc & $01FC).
; - The row-start split-U and cached-V states are now streamed from the per-row
;   table, so the once-per-row rebuild is gone from the hotloop.
; - Each row now streams the exact start Uc word, the exact cached row
;   contribution word, one packed [WLow|Ul] word, and three premerged packed longs for the first
;   three row pairs. This lets the row start restore the exact U/V seed with
;   MOVEM.W, emit a 3-pair prefix directly, and skip three full pair bodies.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
endm                                      ; End of the two-texel processing macro.

; -----------------------------------------------------------------------------
; void RenderFrameAsm(__reg("a0") UBYTE *Dest, __reg("a1") const void *FrameState)
;
; C precomputes the exact split-U and cached-row seed for every frame in the
; fixed 256-step animation cycle. Each compact frame block embeds its 48 row
; seeds directly behind the 8-byte header. C now stores the exact fast-family
; entry pointer for each frame block, so the assembler restores the shared
; per-frame deltas once and jumps straight into the matching real V family
; without paying the variant branch chain every frame. Each row seed now
; carries the fully merged first three pairs plus the exact U/V state after
; that 3-pair prefix. The row start therefore emits pairs 0..2 immediately
; and enters the steady-state body at pair 3, dropping three full runtime
; pair bodies from the hotloop.
; -----------------------------------------------------------------------------

_RenderFrameAsm::                         ; Entry point called from C with plane 0 destination in A0.
    movem.l d2-d7/a2-a6,-(sp)             ; Save only the callee-saved registers that are actually preserved.
    movea.l a0,a5                         ; Keep plane 0 destination in A5.
    lea     ROTO_FRAME_ROWS(a1),a0        ; Form the address of this frame block's 48 embedded packed row seeds.
    move.l  a0,-(sp)                      ; Keep the current row-seed pointer in one local stack slot.
    move.w  ROTO_FRAME_DUC(a1),d3         ; Restore the coarse U delta used by every real family.
    move.b  ROTO_FRAME_DUL(a1),d4         ; Restore the sub-texel U remainder delta.
    move.b  ROTO_FRAME_DVREM(a1),d5       ; Restore the horizontal V remainder into D5 low byte.
    movea.l ROTO_FRAME_ENTRY(a1),a2       ; Load the exact fast-family entry pointer prepared by C.

    movea.l _TexturePackedMidHi,a1        ; Load the texel-0 packed-texture midpoint pointer.
    movea.l _TexturePackedMidLo,a3        ; Load the texel-1 pre-shifted texture base.

    lea     ROTO_PLANE_BYTES(a5),a4       ; Build plane 1 base pointer from plane 0.
    lea     (ROTO_PLANE_BYTES*2)(a5),a6   ; Build plane 2 base pointer from plane 0.
    lea     (ROTO_PLANE_BYTES*3)(a5),a0   ; Build plane 3 base pointer once so the pair store stays postincrement.

    jmp     (a2)                          ; Jump straight into the matching fast family without a variant branch chain.

_RenderFastB0Entry::
    moveq   #(ROTO_ROWS-1),d6            ; Seed the remaining-row counter once and keep it in d6's high word.
    swap    d6                            ; The low byte stays free for the cached W remainder.
    bra.s   .fast_b0_after_swap                ; Enter the first row without performing the loop-back swap.
.fast_b0_loop:
    swap    d6                            ; Move the decremented row counter back into d6's high word.
.fast_b0_after_swap:
    movea.l (sp),a2                       ; Reload the current row-seed pointer from the local stack slot.
    movem.w (a2)+,d0-d2                   ; Restore the exact split-U state, cached row and packed [WLow|Ul] state after pair 2.
    move.w  d2,d6                         ; Copy packed [WLow|Ul] into D6 so its low byte can hold WLow during the row.
    lsr.w   #8,d6                         ; Bring WLow into D6 low byte without touching the row counter in D6 high.

    move.l  (a2)+,d7                      ; Restore the fully merged packed long for preadvanced pair 0.
    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.

    move.l  (a2)+,d7                      ; Restore the fully merged packed long for preadvanced pair 1.
    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.

    move.l  (a2)+,d7                      ; Restore the fully merged packed long for preadvanced pair 2.
    move.l  a2,(sp)                       ; Save the already-advanced next-row pointer back into the local stack slot.
    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    bra     .fast_b0_pair03_start                 ; Skip the now-dead pair-1/pair-2 runtime bodies and enter at pair 3.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
.fast_b0_pair03_start:
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    swap    d6                            ; Bring the precomputed remaining-row counter down for DBRA.
    dbra    d6,.fast_b0_loop             ; Repeat until all 48 precomputed row seeds have been rendered.
    bra.w   RenderDone                  ; Skip the remaining loop families once this exact fast path finishes.


_RenderFastBp1Entry::
    moveq   #(ROTO_ROWS-1),d6            ; Seed the remaining-row counter once and keep it in d6's high word.
    swap    d6                            ; The low byte stays free for the cached W remainder.
    bra.s   .fast_bp1_after_swap                ; Enter the first row without performing the loop-back swap.
.fast_bp1_loop:
    swap    d6                            ; Move the decremented row counter back into d6's high word.
.fast_bp1_after_swap:
    movea.l (sp),a2                       ; Reload the current row-seed pointer from the local stack slot.
    movem.w (a2)+,d0-d2                   ; Restore the exact split-U state, cached row and packed [WLow|Ul] state after pair 2.
    move.w  d2,d6                         ; Copy packed [WLow|Ul] into D6 so its low byte can hold WLow during the row.
    lsr.w   #8,d6                         ; Bring WLow into D6 low byte without touching the row counter in D6 high.

    move.l  (a2)+,d7                      ; Restore the fully merged packed long for preadvanced pair 0.
    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.

    move.l  (a2)+,d7                      ; Restore the fully merged packed long for preadvanced pair 1.
    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.

    move.l  (a2)+,d7                      ; Restore the fully merged packed long for preadvanced pair 2.
    move.l  a2,(sp)                       ; Save the already-advanced next-row pointer back into the local stack slot.
    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    bra     .fast_bp1_pair03_start                 ; Skip the now-dead pair-1/pair-2 runtime bodies and enter at pair 3.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
.fast_bp1_pair03_start:
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
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
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    swap    d6                            ; Bring the precomputed remaining-row counter down for DBRA.
    dbra    d6,.fast_bp1_loop             ; Repeat until all 48 precomputed row seeds have been rendered.
    bra.w   RenderDone                  ; Skip the remaining loop families once this exact fast path finishes.

_RenderFastBm1Entry::
    moveq   #(ROTO_ROWS-1),d6            ; Seed the remaining-row counter once and keep it in d6's high word.
    swap    d6                            ; The low byte stays free for the cached W remainder.
    bra.s   .fast_bm1_after_swap                ; Enter the first row without performing the loop-back swap.
.fast_bm1_loop:
    swap    d6                            ; Move the decremented row counter back into d6's high word.
.fast_bm1_after_swap:
    movea.l (sp),a2                       ; Reload the current row-seed pointer from the local stack slot.
    movem.w (a2)+,d0-d2                   ; Restore the exact split-U state, cached row and packed [WLow|Ul] state after pair 2.
    move.w  d2,d6                         ; Copy packed [WLow|Ul] into D6 so its low byte can hold WLow during the row.
    lsr.w   #8,d6                         ; Bring WLow into D6 low byte without touching the row counter in D6 high.

    move.l  (a2)+,d7                      ; Restore the fully merged packed long for preadvanced pair 0.
    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.

    move.l  (a2)+,d7                      ; Restore the fully merged packed long for preadvanced pair 1.
    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.

    move.l  (a2)+,d7                      ; Restore the fully merged packed long for preadvanced pair 2.
    move.l  a2,(sp)                       ; Save the already-advanced next-row pointer back into the local stack slot.
    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    bra     .fast_bm1_pair03_start                 ; Skip the now-dead pair-1/pair-2 runtime bodies and enter at pair 3.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm11_02                    ; Carry means the wrapped remainder cancelled the row move for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm11_02:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm12_02                    ; Carry means the wrapped remainder cancelled the row move for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm12_02:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm11_03                    ; Carry means the wrapped remainder cancelled the row move for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm11_03:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm12_03                    ; Carry means the wrapped remainder cancelled the row move for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm12_03:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
.fast_bm1_pair03_start:
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm11_04                    ; Carry means the wrapped remainder cancelled the row move for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm11_04:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm12_04                    ; Carry means the wrapped remainder cancelled the row move for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm12_04:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm11_05                    ; Carry means the wrapped remainder cancelled the row move for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm11_05:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm12_05                    ; Carry means the wrapped remainder cancelled the row move for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm12_05:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm11_06                    ; Carry means the wrapped remainder cancelled the row move for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm11_06:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm12_06                    ; Carry means the wrapped remainder cancelled the row move for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm12_06:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm11_07                    ; Carry means the wrapped remainder cancelled the row move for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm11_07:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm12_07                    ; Carry means the wrapped remainder cancelled the row move for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm12_07:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm11_08                    ; Carry means the wrapped remainder cancelled the row move for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm11_08:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm12_08                    ; Carry means the wrapped remainder cancelled the row move for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm12_08:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm11_09                    ; Carry means the wrapped remainder cancelled the row move for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm11_09:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm12_09                    ; Carry means the wrapped remainder cancelled the row move for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm12_09:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm11_10                    ; Carry means the wrapped remainder cancelled the row move for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm11_10:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm12_10                    ; Carry means the wrapped remainder cancelled the row move for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm12_10:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm11_11                    ; Carry means the wrapped remainder cancelled the row move for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm11_11:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm12_11                    ; Carry means the wrapped remainder cancelled the row move for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm12_11:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm11_12                    ; Carry means the wrapped remainder cancelled the row move for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm11_12:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm12_12                    ; Carry means the wrapped remainder cancelled the row move for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm12_12:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm11_13                    ; Carry means the wrapped remainder cancelled the row move for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm11_13:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm12_13                    ; Carry means the wrapped remainder cancelled the row move for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm12_13:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm11_14                    ; Carry means the wrapped remainder cancelled the row move for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm11_14:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm12_14                    ; Carry means the wrapped remainder cancelled the row move for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample moves up by exactly one cached texture row.
.vbm12_14:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    swap    d6                            ; Bring the precomputed remaining-row counter down for DBRA.
    dbra    d6,.fast_bm1_loop             ; Repeat until all 48 precomputed row seeds have been rendered.
    bra.w   RenderDone                  ; Skip the remaining loop families once this exact fast path finishes.

_RenderFastBm2Entry::
    moveq   #(ROTO_ROWS-1),d6            ; Seed the remaining-row counter once and keep it in d6's high word.
    swap    d6                            ; The low byte stays free for the cached W remainder.
    bra.s   .fast_bm2_after_swap                ; Enter the first row without performing the loop-back swap.
.fast_bm2_loop:
    swap    d6                            ; Move the decremented row counter back into d6's high word.
.fast_bm2_after_swap:
    movea.l (sp),a2                       ; Reload the current row-seed pointer from the local stack slot.
    movem.w (a2)+,d0-d2                   ; Restore the exact split-U state, cached row and packed [WLow|Ul] state after pair 2.
    move.w  d2,d6                         ; Copy packed [WLow|Ul] into D6 so its low byte can hold WLow during the row.
    lsr.w   #8,d6                         ; Bring WLow into D6 low byte without touching the row counter in D6 high.

    move.l  (a2)+,d7                      ; Restore the fully merged packed long for preadvanced pair 0.
    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.

    move.l  (a2)+,d7                      ; Restore the fully merged packed long for preadvanced pair 1.
    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.

    move.l  (a2)+,d7                      ; Restore the fully merged packed long for preadvanced pair 2.
    move.l  a2,(sp)                       ; Save the already-advanced next-row pointer back into the local stack slot.
    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    bra     .fast_bm2_pair03_start                 ; Skip the now-dead pair-1/pair-2 runtime bodies and enter at pair 3.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm21_02                    ; Carry means the guaranteed -1 row move was already sufficient for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm21_02:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm22_02                    ; Carry means the guaranteed -1 row move was already sufficient for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm22_02:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm21_03                    ; Carry means the guaranteed -1 row move was already sufficient for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm21_03:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm22_03                    ; Carry means the guaranteed -1 row move was already sufficient for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm22_03:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
.fast_bm2_pair03_start:
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm21_04                    ; Carry means the guaranteed -1 row move was already sufficient for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm21_04:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm22_04                    ; Carry means the guaranteed -1 row move was already sufficient for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm22_04:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm21_05                    ; Carry means the guaranteed -1 row move was already sufficient for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm21_05:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm22_05                    ; Carry means the guaranteed -1 row move was already sufficient for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm22_05:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm21_06                    ; Carry means the guaranteed -1 row move was already sufficient for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm21_06:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm22_06                    ; Carry means the guaranteed -1 row move was already sufficient for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm22_06:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm21_07                    ; Carry means the guaranteed -1 row move was already sufficient for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm21_07:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm22_07                    ; Carry means the guaranteed -1 row move was already sufficient for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm22_07:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm21_08                    ; Carry means the guaranteed -1 row move was already sufficient for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm21_08:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm22_08                    ; Carry means the guaranteed -1 row move was already sufficient for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm22_08:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm21_09                    ; Carry means the guaranteed -1 row move was already sufficient for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm21_09:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm22_09                    ; Carry means the guaranteed -1 row move was already sufficient for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm22_09:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm21_10                    ; Carry means the guaranteed -1 row move was already sufficient for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm21_10:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm22_10                    ; Carry means the guaranteed -1 row move was already sufficient for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm22_10:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm21_11                    ; Carry means the guaranteed -1 row move was already sufficient for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm21_11:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm22_11                    ; Carry means the guaranteed -1 row move was already sufficient for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm22_11:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm21_12                    ; Carry means the guaranteed -1 row move was already sufficient for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm21_12:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm22_12                    ; Carry means the guaranteed -1 row move was already sufficient for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm22_12:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm21_13                    ; Carry means the guaranteed -1 row move was already sufficient for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm21_13:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm22_13                    ; Carry means the guaranteed -1 row move was already sufficient for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm22_13:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    move.w  d0,d7                         ; Copy Uc so the horizontal texel contribution can be derived directly.
    andi.w  #$01FC,d7                     ; Keep the ready-made 4-byte packed-texture offset contribution.
    add.w   d1,d7                         ; Fold the cached packed-texture row contribution into the texel-0 offset in data-register space.
    movea.w d7,a2                         ; Move the final signed packed-texture offset into A2 for the later memory-OR.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction.
    addx.w  d3,d0                         ; Advance the wrapping Uc state with the carried bit from Ul.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte by the wrapped positive remainder.
    bcs.s   .vbm21_14                    ; Carry means the guaranteed -1 row move was already sufficient for this sample.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm21_14:
    move.w  d0,d7                         ; Copy updated Uc for texel two.
    andi.w  #$01FC,d7                     ; Keep texel two's ready-made packed-texture offset contribution.
    add.w   d1,d7                         ; Combine cached row contribution and horizontal texel contribution.
    move.l  (a3,d7.w),d7                  ; Fetch pre-shifted packed contribution for the second texel.
    add.b   d4,d2                         ; Advance the quadrupled 6-bit U subfraction to the next pair's first texel.
    addx.w  d3,d0                         ; Advance the wrapping Uc state to the next pair's first texel.
    subi.w  #$0200,d1                     ; Large negative V steps always move up by at least one cached texture row.
    add.b   d5,d6                         ; Advance cached W low byte to the next pair's first texel.
    bcs.s   .vbm22_14                    ; Carry means the guaranteed -1 row move was already sufficient for sample two.
    subi.w  #$0200,d1                     ; No carry means the sample needs the second cached row decrement, giving a net -2 move.
.vbm22_14:
    or.l    0(a1,a2.w),d7                 ; Merge texel 0 directly from memory into the texel-1 result.

    move.b  d7,(a5)+                      ; Write plane 0 byte and advance plane 0 destination pointer.
    swap    d7                            ; Bring the former high-word plane bytes into the low word.
    move.b  d7,(a6)+                      ; Write plane 2 byte and advance plane 2 destination pointer.
    lsr.l   #8,d7                         ; Shift once across the full longword so plane 3 lands in the low byte.
    move.b  d7,(a0)+                      ; Write plane 3 byte and advance plane 3 destination pointer.
    swap    d7                            ; Bring the saved plane 1 byte into the low byte position.
    move.b  d7,(a4)+                      ; Write plane 1 byte and advance plane 1 destination pointer.
    swap    d6                            ; Bring the precomputed remaining-row counter down for DBRA.
    dbra    d6,.fast_bm2_loop             ; Repeat until all 48 precomputed row seeds have been rendered.
    bra.w   RenderDone                  ; Skip the remaining loop families once this exact fast path finishes.

RenderDone:
    addq.l  #4,sp                         ; Drop the local row-seed pointer slot before restoring registers.
    movem.l (sp)+,d2-d7/a2-a6             ; Restore saved callee-saved registers.
    rts                                    ; Return to the C caller.
