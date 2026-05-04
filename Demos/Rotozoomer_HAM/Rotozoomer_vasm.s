
    machine 68000                          ; Select the plain 68000 instruction set.

    include "lwmf/lwmf_hardware_regs.i"    ; Keep the project hardware include available.


ROTO_ROWS              equ 48         ; Rendered logical rows.
ROTO_PAIR_COUNT        equ 28         ; Logical texel pairs per row.
ROTO_PREFIX_PAIRS      equ 17         ; Pairs covered by the precomputed row prefix (01-17).
ROTO_PLANE_STRIDE      equ 28         ; Bytes per rendered row in one bitplane.
ROTO_PLANE_BYTES       equ (ROTO_PLANE_STRIDE*ROTO_ROWS) ; Bytes in one contiguous rendered bitplane.
ROTO_FRAME_DUC         equ 0          ; Frame offset of the signed integer U step.
ROTO_FRAME_DUL         equ 2          ; Frame offset of the fractional U step byte.
ROTO_FRAME_DVREM       equ 3          ; Frame offset of the fractional V step byte.
ROTO_FRAME_ENTRY       equ 4          ; Frame offset of the selected family entry pointer.
ROTO_FRAME_SEED0       equ 8          ; Frame offset of the first-row packed V row bits and U coordinate.
ROTO_FRAME_REMS0       equ 10         ; Frame offset of the first-row packed V and U fractional remainders.
ROTO_FRAME_POST_DUC    equ 12         ; Frame offset of the post-row signed integer U delta.
ROTO_FRAME_POST_DUL    equ 14         ; Frame offset of the post-row fractional U delta byte.
ROTO_FRAME_POST_VBASE  equ 16         ; Frame offset of the post-row signed V row-base delta in texture bytes.
ROTO_FRAME_POST_VREM   equ 18         ; Frame offset of the post-row V fractional delta shifted into the high byte.
ROTO_FRAME_NEXT        equ 20         ; Frame offset of the variable-sized next-frame pointer.
ROTO_FRAME_ROWS        equ 24         ; Frame offset of the first row prefix state.
ROTO_FRAME_SIZE        equ 0          ; Uniform frame stride (all P13, computed by C side).
ROTO_ROW_PREFIX_PLANES equ 0          ; Row offset of four premerged plane-prefix longs (pairs 01-04).
ROTO_ROW_PREFIX_PAIR56 equ 16         ; Row offset of the fifth and sixth premerged texel pairs as four plane words.
ROTO_ROW_PREFIX_PAIR7  equ 24         ; Row offset of pairs 07-08 plane words.
ROTO_ROW_SIZE          equ 68         ; Size of one uniform P17 row prefix state.
STACK_ROWPTR           equ 0          ; Stack offset of the current row-prefix pointer.
STACK_POST_DUL_BYTE    equ 5          ; Stack byte offset of the post-row fractional U delta.
STACK_POST_DUC         equ 6          ; Stack offset of the post-row integer U delta.
STACK_POST_VBASE       equ 8          ; Stack offset of the post-row V row-base delta.
STACK_POST_VREM        equ 10         ; Stack offset of the post-row V fractional delta.
STACK_TEMP_BYTES       equ 12         ; Bytes of temporary renderer stack data.

; -----------------------------------------------------------------------------
; void RenderFrameAsm(__reg("a0") UBYTE *Dest, __reg("a1") const void *FrameState)
; -----------------------------------------------------------------------------

_RenderFrameAsm::                        ; Entry from C with destination in a0 and frame state in a1.
    movem.l d2-d7/a2-a6,-(sp)              ; Preserve all callee-saved registers used by the renderer.
    movea.l a0,a5                          ; Keep plane 0 destination pointer in a5.
    move.w  ROTO_FRAME_SEED0(a1),d0        ; Load the first-row packed U seed after the prefix.
    move.w  ROTO_FRAME_REMS0(a1),d2        ; Load the first-row packed V/U fractional remainders after the prefix.
    move.w  d0,d1                          ; Copy the packed seed so d1 can become the V row offset.
    andi.w  #$FE00,d1                      ; Keep only the wrapped V row offset in d1.
    move.w  ROTO_FRAME_POST_VREM(a1),-(sp) ; Cache the post-row V fractional delta on the stack.
    move.w  ROTO_FRAME_POST_VBASE(a1),-(sp) ; Cache the post-row V row-base delta on the stack.
    move.w  ROTO_FRAME_POST_DUC(a1),-(sp)  ; Cache the post-row integer U delta on the stack.
    moveq   #0,d7                          ; Clear d7 before caching the byte-sized post-row U fraction.
    move.b  ROTO_FRAME_POST_DUL(a1),d7     ; Load the post-row fractional U delta into the low byte of d7.
    move.w  d7,-(sp)                       ; Cache the post-row fractional U delta as an aligned stack word.
    lea     ROTO_FRAME_ROWS(a1),a0         ; Point a0 at the first row prefix state.
    move.l  a0,-(sp)                       ; Store the current row-prefix pointer in the top stack slot.
    move.w  (a1),d3          ; Load the signed integer U step into d3.
    move.b  ROTO_FRAME_DUL(a1),d4          ; Load the fractional U step into the low byte of d4.
    moveq   #(ROTO_ROWS-1),d5              ; Prepare the DBRA row count in d5.
    swap    d5                             ; Move the row count into the high word of d5.
    move.b  ROTO_FRAME_DVREM(a1),d5        ; Load the fractional V step into the low byte of d5.
    lsl.w   #8,d5                          ; Shift the V step into the high byte of the low word.
    move.w  #$01FC,d6                      ; Keep the wrapped U-byte mask in d6 for all sample offsets.
    movea.l ROTO_FRAME_ENTRY(a1),a2        ; Load the selected row-loop entry address.

    movea.l _TexturePackedMidHi,a1         ; Load the centered high-nibble texture table base.
    movea.l _TexturePackedMidLo,a3         ; Load the centered low-nibble texture table base.

    lea     ROTO_PLANE_BYTES(a5),a4        ; Point a4 at plane 1.
    lea     (ROTO_PLANE_BYTES*2)(a5),a6    ; Point a6 at plane 2.
    lea     (ROTO_PLANE_BYTES*3)(a5),a0    ; Point a0 at plane 3.

    jmp     (a2)                           ; Jump into the family-specific unrolled row loop.

_RenderFastB0P8Entry::                  ; Family entry for zero integer V row base and integrated pair 08.
    bra.s   .fast_b0p8_after_swap            ; Enter the first row without applying the post-row delta.
.fast_b0p8_loop:                           ; Start of the next logical row after DBRA branched.
    swap    d5                             ; Restore row count to the high word and V step to the low word.
.fast_b0p8_post_row:                       ; Advance the rolling U/V seed from the previous row end to this row prefix.
    add.b   STACK_POST_DUL_BYTE(sp),d2     ; Apply the post-row fractional U delta and set X for the integer carry.
    move.w  STACK_POST_DUC(sp),d7          ; Load the post-row integer U delta into scratch register d7.
    addx.w  d7,d0                          ; Apply the post-row integer U delta plus the fractional carry.
    add.w   STACK_POST_VBASE(sp),d1        ; Apply the signed V row-base delta in texture-byte units.
    add.w   STACK_POST_VREM(sp),d2         ; Apply the post-row V fractional delta and set carry on row crossing.
    bcc.s   .fast_b0p8_post_no_vcarry        ; Skip the extra V row increment when the post-row fraction did not wrap.
    addi.w  #$0200,d1                      ; Apply the extra V row increment produced by the post-row fractional carry.
.fast_b0p8_post_no_vcarry:                 ; Post-row V carry handling is complete.
.fast_b0p8_after_swap:                     ; Row setup with the rolling seed already prepared for this row.
    movea.l (sp),a2            ; Reload the current row-prefix pointer from the stack slot.

    move.l  (a2)+,(a5)+                    ; Copy prefix pairs 01-04 directly from row state to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix pairs 01-04 directly from row state to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix pairs 01-04 directly from row state to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix pairs 01-04 directly from row state to plane 3.

.fast_b0p8_pair05_06_prefix:               ; Emit prefix pairs 05-06 as direct plane words.
    move.w  (a2)+,(a5)+                    ; Pairs 05-06: copy the two premerged plane 0 bytes and advance plane 0.
    move.w  (a2)+,(a4)+                    ; Pairs 05-06: copy the two premerged plane 1 bytes and advance plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 05-06: copy the two premerged plane 2 bytes and advance plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 05-06: copy the two premerged plane 3 bytes and advance plane 3.

.fast_b0p8_pair07_08_prefix:            ; Emit integrated prefix pairs 07-08 as direct plane words.
    move.w  (a2)+,(a5)+                    ; Pairs 07-08: copy the two premerged plane 0 bytes and advance plane 0.
    move.w  (a2)+,(a4)+                    ; Pairs 07-08: copy the two premerged plane 1 bytes and advance plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 07-08: copy the two premerged plane 2 bytes and advance plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 07-08: copy the two premerged plane 3 bytes and advance plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 09-10: copy packed word to plane 0 (high byte = pair 09, low byte = pair 10).
    move.w  (a2)+,(a4)+                    ; Pairs 09-10: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 09-10: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 09-10: copy packed word to plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 11-12: copy packed word to plane 0 (high byte = pair 11, low byte = pair 12).
    move.w  (a2)+,(a4)+                    ; Pairs 11-12: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 11-12: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 11-12: copy packed word to plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 13-14: copy packed word to plane 0 (high byte = pair 13, low byte = pair 14).
    move.w  (a2)+,(a4)+                    ; Pairs 13-14: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 13-14: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 13-14: copy packed word to plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 15: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 15: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 15: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 15: copy precomputed plane 3 byte and advance plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 16: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 16: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 16: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 16: copy precomputed plane 3 byte and advance plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 17: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 17: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 17: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 17: copy precomputed plane 3 byte and advance plane 3.
    move.l  a2,(sp)            ; Store the next row-prefix pointer after the integrated pair 17 bytes.

    move.w  d0,d7                          ; Pair 18 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 18 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 18 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 18 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 18 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 18 sample 1: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 18 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vb01_18_fast_b0p8               ; Pair 18 sample 1: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 18 sample 1: advance one wrapped texture row after V carry.
.vb01_18_fast_b0p8:                        ; Pair 18 sample 1: V update complete for zero-base family.
    move.w  d0,d7                          ; Pair 18 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 18 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 18 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 18 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 18 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 18 sample 2: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 18 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vb02_18_fast_b0p8               ; Pair 18 sample 2: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 18 sample 2: advance one wrapped texture row after V carry.
.vb02_18_fast_b0p8:                        ; Pair 18 sample 2: V update complete for zero-base family.
    or.l    (a1,a2.w),d7                  ; Pair 18: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 18: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 18: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 18: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 18: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 18: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 18: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 18: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 19 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 19 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 19 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 19 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 19 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 19 sample 1: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 19 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vb01_19_fast_b0p8               ; Pair 19 sample 1: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 19 sample 1: advance one wrapped texture row after V carry.
.vb01_19_fast_b0p8:                        ; Pair 19 sample 1: V update complete for zero-base family.
    move.w  d0,d7                          ; Pair 19 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 19 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 19 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 19 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 19 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 19 sample 2: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 19 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vb02_19_fast_b0p8               ; Pair 19 sample 2: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 19 sample 2: advance one wrapped texture row after V carry.
.vb02_19_fast_b0p8:                        ; Pair 19 sample 2: V update complete for zero-base family.
    or.l    (a1,a2.w),d7                  ; Pair 19: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 19: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 19: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 19: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 19: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 19: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 19: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 19: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 20 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 20 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 20 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 20 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 20 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 20 sample 1: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 20 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vb01_20_fast_b0p8               ; Pair 20 sample 1: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 20 sample 1: advance one wrapped texture row after V carry.
.vb01_20_fast_b0p8:                        ; Pair 20 sample 1: V update complete for zero-base family.
    move.w  d0,d7                          ; Pair 20 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 20 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 20 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 20 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 20 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 20 sample 2: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 20 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vb02_20_fast_b0p8               ; Pair 20 sample 2: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 20 sample 2: advance one wrapped texture row after V carry.
.vb02_20_fast_b0p8:                        ; Pair 20 sample 2: V update complete for zero-base family.
    or.l    (a1,a2.w),d7                  ; Pair 20: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 20: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 20: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 20: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 20: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 20: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 20: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 20: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 21 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 21 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 21 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 21 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 21 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 21 sample 1: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 21 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vb01_21_fast_b0p8               ; Pair 21 sample 1: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 21 sample 1: advance one wrapped texture row after V carry.
.vb01_21_fast_b0p8:                        ; Pair 21 sample 1: V update complete for zero-base family.
    move.w  d0,d7                          ; Pair 21 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 21 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 21 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 21 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 21 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 21 sample 2: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 21 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vb02_21_fast_b0p8               ; Pair 21 sample 2: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 21 sample 2: advance one wrapped texture row after V carry.
.vb02_21_fast_b0p8:                        ; Pair 21 sample 2: V update complete for zero-base family.
    or.l    (a1,a2.w),d7                  ; Pair 21: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 21: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 21: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 21: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 21: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 21: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 21: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 21: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 22 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 22 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 22 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 22 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 22 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 22 sample 1: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 22 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vb01_22_fast_b0p8               ; Pair 22 sample 1: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 22 sample 1: advance one wrapped texture row after V carry.
.vb01_22_fast_b0p8:                        ; Pair 22 sample 1: V update complete for zero-base family.
    move.w  d0,d7                          ; Pair 22 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 22 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 22 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 22 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 22 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 22 sample 2: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 22 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vb02_22_fast_b0p8               ; Pair 22 sample 2: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 22 sample 2: advance one wrapped texture row after V carry.
.vb02_22_fast_b0p8:                        ; Pair 22 sample 2: V update complete for zero-base family.
    or.l    (a1,a2.w),d7                  ; Pair 22: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 22: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 22: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 22: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 22: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 22: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 22: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 22: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 23 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 23 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 23 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 23 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 23 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 23 sample 1: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 23 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vb01_23_fast_b0p8               ; Pair 23 sample 1: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 23 sample 1: advance one wrapped texture row after V carry.
.vb01_23_fast_b0p8:                        ; Pair 23 sample 1: V update complete for zero-base family.
    move.w  d0,d7                          ; Pair 23 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 23 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 23 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 23 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 23 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 23 sample 2: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 23 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vb02_23_fast_b0p8               ; Pair 23 sample 2: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 23 sample 2: advance one wrapped texture row after V carry.
.vb02_23_fast_b0p8:                        ; Pair 23 sample 2: V update complete for zero-base family.
    or.l    (a1,a2.w),d7                  ; Pair 23: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 23: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 23: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 23: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 23: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 23: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 23: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 23: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 24 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 24 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 24 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 24 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 24 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 24 sample 1: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 24 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vb01_24_fast_b0p8               ; Pair 24 sample 1: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 24 sample 1: advance one wrapped texture row after V carry.
.vb01_24_fast_b0p8:                        ; Pair 24 sample 1: V update complete for zero-base family.
    move.w  d0,d7                          ; Pair 24 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 24 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 24 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 24 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 24 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 24 sample 2: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 24 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vb02_24_fast_b0p8               ; Pair 24 sample 2: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 24 sample 2: advance one wrapped texture row after V carry.
.vb02_24_fast_b0p8:                        ; Pair 24 sample 2: V update complete for zero-base family.
    or.l    (a1,a2.w),d7                  ; Pair 24: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 24: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 24: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 24: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 24: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 24: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 24: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 24: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 25 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 25 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 25 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 25 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 25 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 25 sample 1: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 25 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vb01_25_fast_b0p8               ; Pair 25 sample 1: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 25 sample 1: advance one wrapped texture row after V carry.
.vb01_25_fast_b0p8:                        ; Pair 25 sample 1: V update complete for zero-base family.
    move.w  d0,d7                          ; Pair 25 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 25 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 25 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 25 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 25 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 25 sample 2: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 25 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vb02_25_fast_b0p8               ; Pair 25 sample 2: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 25 sample 2: advance one wrapped texture row after V carry.
.vb02_25_fast_b0p8:                        ; Pair 25 sample 2: V update complete for zero-base family.
    or.l    (a1,a2.w),d7                  ; Pair 25: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 25: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 25: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 25: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 25: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 25: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 25: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 25: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 26 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 26 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 26 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 26 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 26 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 26 sample 1: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 26 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vb01_26_fast_b0p8               ; Pair 26 sample 1: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 26 sample 1: advance one wrapped texture row after V carry.
.vb01_26_fast_b0p8:                        ; Pair 26 sample 1: V update complete for zero-base family.
    move.w  d0,d7                          ; Pair 26 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 26 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 26 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 26 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 26 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 26 sample 2: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 26 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vb02_26_fast_b0p8               ; Pair 26 sample 2: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 26 sample 2: advance one wrapped texture row after V carry.
.vb02_26_fast_b0p8:                        ; Pair 26 sample 2: V update complete for zero-base family.
    or.l    (a1,a2.w),d7                  ; Pair 26: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 26: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 26: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 26: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 26: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 26: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 26: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 26: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 27 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 27 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 27 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 27 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 27 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 27 sample 1: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 27 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vb01_27_fast_b0p8               ; Pair 27 sample 1: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 27 sample 1: advance one wrapped texture row after V carry.
.vb01_27_fast_b0p8:                        ; Pair 27 sample 1: V update complete for zero-base family.
    move.w  d0,d7                          ; Pair 27 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 27 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 27 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 27 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 27 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 27 sample 2: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 27 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vb02_27_fast_b0p8               ; Pair 27 sample 2: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 27 sample 2: advance one wrapped texture row after V carry.
.vb02_27_fast_b0p8:                        ; Pair 27 sample 2: V update complete for zero-base family.
    or.l    (a1,a2.w),d7                  ; Pair 27: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 27: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 27: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 27: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 27: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 27: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 27: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 27: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 28 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 28 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 28 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 28 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 28 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 28 sample 1: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 28 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vb01_28_fast_b0p8               ; Pair 28 sample 1: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 28 sample 1: advance one wrapped texture row after V carry.
.vb01_28_fast_b0p8:                        ; Pair 28 sample 1: V update complete for zero-base family.
    move.w  d0,d7                          ; Pair 28 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 28 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 28 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 28 sample 2: fetch the low-nibble contribution into d7.
    ;                                      ; Pair 28 sample 2: skip the final accumulator update; post-row delta includes it.
    or.l    (a1,a2.w),d7                  ; Pair 28: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 28: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 28: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 28: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 28: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 28: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 28: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 28: store plane 1 byte and advance plane 1.
    swap    d5                             ; Move the row count into the low word for DBRA.
    dbra    d5,.fast_b0p8_loop               ; Render the next logical row until all rows are complete.
    lea     STACK_TEMP_BYTES(sp),sp        ; Discard the temporary row-prefix and post-row stack slots.
    movem.l (sp)+,d2-d7/a2-a6              ; Restore all preserved registers.
    rts                                    ; Return to the C main loop without an extra final branch.

_RenderFastBm1P8Entry::                    ; Family entry for minus-one integer V row base and integrated pair 08.
    bra.s   .fast_bm1_after_swap           ; Enter the first row without applying the post-row delta.
.fast_bm1_loop:                          ; Start of the next logical row after DBRA branched.
    swap    d5                             ; Restore row count to the high word and V step to the low word.
.fast_bm1_post_row:                      ; Advance the rolling U/V seed from the previous row end to this row prefix.
    add.b   STACK_POST_DUL_BYTE(sp),d2     ; Apply the post-row fractional U delta and set X for the integer carry.
    move.w  STACK_POST_DUC(sp),d7          ; Load the post-row integer U delta into scratch register d7.
    addx.w  d7,d0                          ; Apply the post-row integer U delta plus the fractional carry.
    add.w   STACK_POST_VBASE(sp),d1        ; Apply the signed V row-base delta in texture-byte units.
    add.w   STACK_POST_VREM(sp),d2         ; Apply the post-row V fractional delta and set carry on row crossing.
    bcc.s   .fast_bm1_post_no_vcarry       ; Skip the extra V row increment when the post-row fraction did not wrap.
    addi.w  #$0200,d1                      ; Apply the extra V row increment produced by the post-row fractional carry.
.fast_bm1_post_no_vcarry:                ; Post-row V carry handling is complete.
.fast_bm1_after_swap:                    ; Row setup with the rolling seed already prepared for this row.
    movea.l (sp),a2            ; Reload the current row-prefix pointer from the stack slot.

    move.l  (a2)+,(a5)+                    ; Copy prefix pairs 01-04 directly from row state to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix pairs 01-04 directly from row state to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix pairs 01-04 directly from row state to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix pairs 01-04 directly from row state to plane 3.

.fast_bm1_pair05_06_prefix:              ; Emit prefix pairs 05-06 as direct plane words.
    move.w  (a2)+,(a5)+                    ; Pairs 05-06: copy the two premerged plane 0 bytes and advance plane 0.
    move.w  (a2)+,(a4)+                    ; Pairs 05-06: copy the two premerged plane 1 bytes and advance plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 05-06: copy the two premerged plane 2 bytes and advance plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 05-06: copy the two premerged plane 3 bytes and advance plane 3.

.fast_bm1_pair07_08_prefix:            ; Emit integrated prefix pairs 07-08 as direct plane words.
    move.w  (a2)+,(a5)+                    ; Pairs 07-08: copy the two premerged plane 0 bytes and advance plane 0.
    move.w  (a2)+,(a4)+                    ; Pairs 07-08: copy the two premerged plane 1 bytes and advance plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 07-08: copy the two premerged plane 2 bytes and advance plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 07-08: copy the two premerged plane 3 bytes and advance plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 09-10: copy packed word to plane 0 (high byte = pair 09, low byte = pair 10).
    move.w  (a2)+,(a4)+                    ; Pairs 09-10: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 09-10: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 09-10: copy packed word to plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 11-12: copy packed word to plane 0 (high byte = pair 11, low byte = pair 12).
    move.w  (a2)+,(a4)+                    ; Pairs 11-12: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 11-12: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 11-12: copy packed word to plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 13-14: copy packed word to plane 0 (high byte = pair 13, low byte = pair 14).
    move.w  (a2)+,(a4)+                    ; Pairs 13-14: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 13-14: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 13-14: copy packed word to plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 15: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 15: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 15: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 15: copy precomputed plane 3 byte and advance plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 16: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 16: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 16: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 16: copy precomputed plane 3 byte and advance plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 17: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 17: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 17: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 17: copy precomputed plane 3 byte and advance plane 3.
    move.l  a2,(sp)            ; Store the next row-prefix pointer after the integrated pair 17 bytes.

    move.w  d0,d7                          ; Pair 18 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 18 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 18 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 18 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 18 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 18 sample 1: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 18 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm11_18_fast_bm1             ; Pair 18 sample 1: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 18 sample 1: decrement one wrapped texture row without carry.
.vbm11_18_fast_bm1:                      ; Pair 18 sample 1: V update complete for minus-one family.
    move.w  d0,d7                          ; Pair 18 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 18 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 18 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 18 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 18 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 18 sample 2: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 18 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm12_18_fast_bm1             ; Pair 18 sample 2: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 18 sample 2: decrement one wrapped texture row without carry.
.vbm12_18_fast_bm1:                      ; Pair 18 sample 2: V update complete for minus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 18: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 18: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 18: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 18: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 18: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 18: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 18: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 18: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 19 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 19 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 19 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 19 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 19 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 19 sample 1: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 19 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm11_19_fast_bm1             ; Pair 19 sample 1: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 19 sample 1: decrement one wrapped texture row without carry.
.vbm11_19_fast_bm1:                      ; Pair 19 sample 1: V update complete for minus-one family.
    move.w  d0,d7                          ; Pair 19 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 19 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 19 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 19 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 19 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 19 sample 2: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 19 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm12_19_fast_bm1             ; Pair 19 sample 2: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 19 sample 2: decrement one wrapped texture row without carry.
.vbm12_19_fast_bm1:                      ; Pair 19 sample 2: V update complete for minus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 19: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 19: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 19: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 19: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 19: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 19: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 19: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 19: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 20 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 20 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 20 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 20 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 20 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 20 sample 1: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 20 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm11_20_fast_bm1             ; Pair 20 sample 1: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 20 sample 1: decrement one wrapped texture row without carry.
.vbm11_20_fast_bm1:                      ; Pair 20 sample 1: V update complete for minus-one family.
    move.w  d0,d7                          ; Pair 20 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 20 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 20 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 20 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 20 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 20 sample 2: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 20 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm12_20_fast_bm1             ; Pair 20 sample 2: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 20 sample 2: decrement one wrapped texture row without carry.
.vbm12_20_fast_bm1:                      ; Pair 20 sample 2: V update complete for minus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 20: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 20: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 20: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 20: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 20: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 20: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 20: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 20: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 21 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 21 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 21 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 21 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 21 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 21 sample 1: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 21 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm11_21_fast_bm1             ; Pair 21 sample 1: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 21 sample 1: decrement one wrapped texture row without carry.
.vbm11_21_fast_bm1:                      ; Pair 21 sample 1: V update complete for minus-one family.
    move.w  d0,d7                          ; Pair 21 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 21 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 21 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 21 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 21 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 21 sample 2: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 21 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm12_21_fast_bm1             ; Pair 21 sample 2: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 21 sample 2: decrement one wrapped texture row without carry.
.vbm12_21_fast_bm1:                      ; Pair 21 sample 2: V update complete for minus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 21: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 21: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 21: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 21: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 21: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 21: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 21: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 21: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 22 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 22 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 22 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 22 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 22 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 22 sample 1: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 22 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm11_22_fast_bm1             ; Pair 22 sample 1: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 22 sample 1: decrement one wrapped texture row without carry.
.vbm11_22_fast_bm1:                      ; Pair 22 sample 1: V update complete for minus-one family.
    move.w  d0,d7                          ; Pair 22 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 22 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 22 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 22 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 22 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 22 sample 2: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 22 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm12_22_fast_bm1             ; Pair 22 sample 2: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 22 sample 2: decrement one wrapped texture row without carry.
.vbm12_22_fast_bm1:                      ; Pair 22 sample 2: V update complete for minus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 22: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 22: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 22: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 22: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 22: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 22: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 22: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 22: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 23 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 23 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 23 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 23 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 23 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 23 sample 1: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 23 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm11_23_fast_bm1             ; Pair 23 sample 1: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 23 sample 1: decrement one wrapped texture row without carry.
.vbm11_23_fast_bm1:                      ; Pair 23 sample 1: V update complete for minus-one family.
    move.w  d0,d7                          ; Pair 23 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 23 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 23 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 23 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 23 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 23 sample 2: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 23 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm12_23_fast_bm1             ; Pair 23 sample 2: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 23 sample 2: decrement one wrapped texture row without carry.
.vbm12_23_fast_bm1:                      ; Pair 23 sample 2: V update complete for minus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 23: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 23: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 23: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 23: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 23: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 23: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 23: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 23: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 24 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 24 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 24 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 24 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 24 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 24 sample 1: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 24 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm11_24_fast_bm1             ; Pair 24 sample 1: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 24 sample 1: decrement one wrapped texture row without carry.
.vbm11_24_fast_bm1:                      ; Pair 24 sample 1: V update complete for minus-one family.
    move.w  d0,d7                          ; Pair 24 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 24 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 24 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 24 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 24 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 24 sample 2: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 24 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm12_24_fast_bm1             ; Pair 24 sample 2: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 24 sample 2: decrement one wrapped texture row without carry.
.vbm12_24_fast_bm1:                      ; Pair 24 sample 2: V update complete for minus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 24: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 24: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 24: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 24: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 24: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 24: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 24: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 24: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 25 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 25 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 25 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 25 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 25 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 25 sample 1: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 25 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm11_25_fast_bm1             ; Pair 25 sample 1: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 25 sample 1: decrement one wrapped texture row without carry.
.vbm11_25_fast_bm1:                      ; Pair 25 sample 1: V update complete for minus-one family.
    move.w  d0,d7                          ; Pair 25 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 25 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 25 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 25 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 25 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 25 sample 2: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 25 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm12_25_fast_bm1             ; Pair 25 sample 2: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 25 sample 2: decrement one wrapped texture row without carry.
.vbm12_25_fast_bm1:                      ; Pair 25 sample 2: V update complete for minus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 25: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 25: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 25: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 25: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 25: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 25: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 25: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 25: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 26 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 26 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 26 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 26 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 26 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 26 sample 1: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 26 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm11_26_fast_bm1             ; Pair 26 sample 1: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 26 sample 1: decrement one wrapped texture row without carry.
.vbm11_26_fast_bm1:                      ; Pair 26 sample 1: V update complete for minus-one family.
    move.w  d0,d7                          ; Pair 26 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 26 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 26 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 26 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 26 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 26 sample 2: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 26 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm12_26_fast_bm1             ; Pair 26 sample 2: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 26 sample 2: decrement one wrapped texture row without carry.
.vbm12_26_fast_bm1:                      ; Pair 26 sample 2: V update complete for minus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 26: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 26: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 26: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 26: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 26: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 26: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 26: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 26: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 27 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 27 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 27 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 27 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 27 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 27 sample 1: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 27 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm11_27_fast_bm1             ; Pair 27 sample 1: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 27 sample 1: decrement one wrapped texture row without carry.
.vbm11_27_fast_bm1:                      ; Pair 27 sample 1: V update complete for minus-one family.
    move.w  d0,d7                          ; Pair 27 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 27 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 27 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 27 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 27 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 27 sample 2: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 27 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm12_27_fast_bm1             ; Pair 27 sample 2: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 27 sample 2: decrement one wrapped texture row without carry.
.vbm12_27_fast_bm1:                      ; Pair 27 sample 2: V update complete for minus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 27: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 27: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 27: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 27: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 27: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 27: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 27: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 27: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 28 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 28 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 28 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 28 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 28 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 28 sample 1: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 28 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm11_28_fast_bm1             ; Pair 28 sample 1: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 28 sample 1: decrement one wrapped texture row without carry.
.vbm11_28_fast_bm1:                      ; Pair 28 sample 1: V update complete for minus-one family.
    move.w  d0,d7                          ; Pair 28 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 28 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 28 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 28 sample 2: fetch the low-nibble contribution into d7.
    ;                                      ; Pair 28 sample 2: skip the final accumulator update; post-row delta includes it.
    or.l    (a1,a2.w),d7                  ; Pair 28: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 28: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 28: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 28: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 28: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 28: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 28: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 28: store plane 1 byte and advance plane 1.
    swap    d5                             ; Move the row count into the low word for DBRA.
    dbra    d5,.fast_bm1_loop              ; Render the next logical row until all rows are complete.
    lea     STACK_TEMP_BYTES(sp),sp        ; Discard the temporary row-prefix and post-row stack slots.
    movem.l (sp)+,d2-d7/a2-a6              ; Restore all preserved registers.
    rts                                    ; Return to the C main loop without an extra final branch.


_RenderFastB0U0P8Entry::                  ; Family entry for zero integer V row base and integrated pair 08.
    bra.s   .fast_b0u0p8_after_swap            ; Enter the first row without applying the post-row delta.
.fast_b0u0p8_loop:                           ; Start of the next logical row after DBRA branched.
    swap    d5                             ; Restore row count to the high word and V step to the low word.
.fast_b0u0p8_post_row:                       ; Advance the rolling U/V seed from the previous row end to this row prefix.
    add.b   STACK_POST_DUL_BYTE(sp),d2     ; Apply the post-row fractional U delta and set X for the integer carry.
    move.w  STACK_POST_DUC(sp),d7          ; Load the post-row integer U delta into scratch register d7.
    addx.w  d7,d0                          ; Apply the post-row integer U delta plus the fractional carry.
    add.w   STACK_POST_VBASE(sp),d1        ; Apply the signed V row-base delta in texture-byte units.
    add.w   STACK_POST_VREM(sp),d2         ; Apply the post-row V fractional delta and set carry on row crossing.
    bcc.s   .fast_b0u0p8_post_no_vcarry        ; Skip the extra V row increment when the post-row fraction did not wrap.
    addi.w  #$0200,d1                      ; Apply the extra V row increment produced by the post-row fractional carry.
.fast_b0u0p8_post_no_vcarry:                 ; Post-row V carry handling is complete.
.fast_b0u0p8_after_swap:                     ; Row setup with the rolling seed already prepared for this row.
    movea.l (sp),a2            ; Reload the current row-prefix pointer from the stack slot.

    move.l  (a2)+,(a5)+                    ; Copy prefix pairs 01-04 directly from row state to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix pairs 01-04 directly from row state to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix pairs 01-04 directly from row state to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix pairs 01-04 directly from row state to plane 3.

.fast_b0u0p8_pair05_06_prefix:               ; Emit prefix pairs 05-06 as direct plane words.
    move.w  (a2)+,(a5)+                    ; Pairs 05-06: copy the two premerged plane 0 bytes and advance plane 0.
    move.w  (a2)+,(a4)+                    ; Pairs 05-06: copy the two premerged plane 1 bytes and advance plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 05-06: copy the two premerged plane 2 bytes and advance plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 05-06: copy the two premerged plane 3 bytes and advance plane 3.

.fast_b0u0p8_pair07_08_prefix:            ; Emit integrated prefix pairs 07-08 as direct plane words.
    move.w  (a2)+,(a5)+                    ; Pairs 07-08: copy the two premerged plane 0 bytes and advance plane 0.
    move.w  (a2)+,(a4)+                    ; Pairs 07-08: copy the two premerged plane 1 bytes and advance plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 07-08: copy the two premerged plane 2 bytes and advance plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 07-08: copy the two premerged plane 3 bytes and advance plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 09-10: copy packed word to plane 0 (high byte = pair 09, low byte = pair 10).
    move.w  (a2)+,(a4)+                    ; Pairs 09-10: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 09-10: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 09-10: copy packed word to plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 11-12: copy packed word to plane 0 (high byte = pair 11, low byte = pair 12).
    move.w  (a2)+,(a4)+                    ; Pairs 11-12: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 11-12: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 11-12: copy packed word to plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 13-14: copy packed word to plane 0 (high byte = pair 13, low byte = pair 14).
    move.w  (a2)+,(a4)+                    ; Pairs 13-14: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 13-14: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 13-14: copy packed word to plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 15: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 15: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 15: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 15: copy precomputed plane 3 byte and advance plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 16: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 16: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 16: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 16: copy precomputed plane 3 byte and advance plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 17: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 17: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 17: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 17: copy precomputed plane 3 byte and advance plane 3.
    move.l  a2,(sp)            ; Store the next row-prefix pointer after the integrated pair 17 bytes.

    move.w  d0,d7                          ; Pair 18 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 18 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 18 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 18 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 18 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vb01_18_fast_b0p8               ; Pair 18 sample 1: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 18 sample 1: advance one wrapped texture row after V carry.
.vb01_18_fast_b0p8:                        ; Pair 18 sample 1: V update complete for zero-base family.
    move.w  d0,d7                          ; Pair 18 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 18 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 18 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 18 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 18 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vb02_18_fast_b0p8               ; Pair 18 sample 2: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 18 sample 2: advance one wrapped texture row after V carry.
.vb02_18_fast_b0p8:                        ; Pair 18 sample 2: V update complete for zero-base family.
    or.l    (a1,a2.w),d7                  ; Pair 18: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 18: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 18: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 18: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 18: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 18: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 18: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 18: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 19 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 19 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 19 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 19 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 19 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vb01_19_fast_b0p8               ; Pair 19 sample 1: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 19 sample 1: advance one wrapped texture row after V carry.
.vb01_19_fast_b0p8:                        ; Pair 19 sample 1: V update complete for zero-base family.
    move.w  d0,d7                          ; Pair 19 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 19 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 19 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 19 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 19 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vb02_19_fast_b0p8               ; Pair 19 sample 2: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 19 sample 2: advance one wrapped texture row after V carry.
.vb02_19_fast_b0p8:                        ; Pair 19 sample 2: V update complete for zero-base family.
    or.l    (a1,a2.w),d7                  ; Pair 19: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 19: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 19: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 19: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 19: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 19: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 19: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 19: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 20 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 20 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 20 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 20 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 20 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vb01_20_fast_b0p8               ; Pair 20 sample 1: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 20 sample 1: advance one wrapped texture row after V carry.
.vb01_20_fast_b0p8:                        ; Pair 20 sample 1: V update complete for zero-base family.
    move.w  d0,d7                          ; Pair 20 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 20 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 20 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 20 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 20 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vb02_20_fast_b0p8               ; Pair 20 sample 2: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 20 sample 2: advance one wrapped texture row after V carry.
.vb02_20_fast_b0p8:                        ; Pair 20 sample 2: V update complete for zero-base family.
    or.l    (a1,a2.w),d7                  ; Pair 20: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 20: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 20: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 20: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 20: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 20: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 20: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 20: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 21 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 21 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 21 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 21 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 21 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vb01_21_fast_b0p8               ; Pair 21 sample 1: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 21 sample 1: advance one wrapped texture row after V carry.
.vb01_21_fast_b0p8:                        ; Pair 21 sample 1: V update complete for zero-base family.
    move.w  d0,d7                          ; Pair 21 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 21 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 21 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 21 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 21 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vb02_21_fast_b0p8               ; Pair 21 sample 2: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 21 sample 2: advance one wrapped texture row after V carry.
.vb02_21_fast_b0p8:                        ; Pair 21 sample 2: V update complete for zero-base family.
    or.l    (a1,a2.w),d7                  ; Pair 21: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 21: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 21: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 21: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 21: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 21: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 21: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 21: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 22 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 22 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 22 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 22 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 22 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vb01_22_fast_b0p8               ; Pair 22 sample 1: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 22 sample 1: advance one wrapped texture row after V carry.
.vb01_22_fast_b0p8:                        ; Pair 22 sample 1: V update complete for zero-base family.
    move.w  d0,d7                          ; Pair 22 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 22 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 22 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 22 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 22 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vb02_22_fast_b0p8               ; Pair 22 sample 2: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 22 sample 2: advance one wrapped texture row after V carry.
.vb02_22_fast_b0p8:                        ; Pair 22 sample 2: V update complete for zero-base family.
    or.l    (a1,a2.w),d7                  ; Pair 22: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 22: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 22: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 22: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 22: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 22: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 22: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 22: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 23 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 23 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 23 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 23 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 23 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vb01_23_fast_b0p8               ; Pair 23 sample 1: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 23 sample 1: advance one wrapped texture row after V carry.
.vb01_23_fast_b0p8:                        ; Pair 23 sample 1: V update complete for zero-base family.
    move.w  d0,d7                          ; Pair 23 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 23 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 23 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 23 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 23 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vb02_23_fast_b0p8               ; Pair 23 sample 2: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 23 sample 2: advance one wrapped texture row after V carry.
.vb02_23_fast_b0p8:                        ; Pair 23 sample 2: V update complete for zero-base family.
    or.l    (a1,a2.w),d7                  ; Pair 23: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 23: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 23: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 23: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 23: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 23: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 23: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 23: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 24 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 24 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 24 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 24 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 24 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vb01_24_fast_b0p8               ; Pair 24 sample 1: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 24 sample 1: advance one wrapped texture row after V carry.
.vb01_24_fast_b0p8:                        ; Pair 24 sample 1: V update complete for zero-base family.
    move.w  d0,d7                          ; Pair 24 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 24 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 24 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 24 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 24 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vb02_24_fast_b0p8               ; Pair 24 sample 2: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 24 sample 2: advance one wrapped texture row after V carry.
.vb02_24_fast_b0p8:                        ; Pair 24 sample 2: V update complete for zero-base family.
    or.l    (a1,a2.w),d7                  ; Pair 24: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 24: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 24: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 24: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 24: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 24: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 24: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 24: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 25 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 25 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 25 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 25 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 25 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vb01_25_fast_b0p8               ; Pair 25 sample 1: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 25 sample 1: advance one wrapped texture row after V carry.
.vb01_25_fast_b0p8:                        ; Pair 25 sample 1: V update complete for zero-base family.
    move.w  d0,d7                          ; Pair 25 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 25 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 25 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 25 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 25 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vb02_25_fast_b0p8               ; Pair 25 sample 2: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 25 sample 2: advance one wrapped texture row after V carry.
.vb02_25_fast_b0p8:                        ; Pair 25 sample 2: V update complete for zero-base family.
    or.l    (a1,a2.w),d7                  ; Pair 25: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 25: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 25: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 25: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 25: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 25: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 25: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 25: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 26 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 26 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 26 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 26 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 26 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vb01_26_fast_b0p8               ; Pair 26 sample 1: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 26 sample 1: advance one wrapped texture row after V carry.
.vb01_26_fast_b0p8:                        ; Pair 26 sample 1: V update complete for zero-base family.
    move.w  d0,d7                          ; Pair 26 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 26 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 26 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 26 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 26 sample 2: advance integer U without fractional carry.
    add.w   d5,d2                          ; Pair 26 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vb02_26_fast_b0u0p8               ; Pair 26 sample 2: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 26 sample 2: advance one wrapped texture row after V carry.
.vb02_26_fast_b0u0p8:                        ; Pair 26 sample 2: V update complete for zero-base family.
    or.l    (a1,a2.w),d7                  ; Pair 26: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 26: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 26: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 26: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 26: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 26: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 26: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 26: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 27 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 27 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 27 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 27 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 27 sample 1: advance integer U without fractional carry.
    add.w   d5,d2                          ; Pair 27 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vb01_27_fast_b0u0p8               ; Pair 27 sample 1: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 27 sample 1: advance one wrapped texture row after V carry.
.vb01_27_fast_b0u0p8:                        ; Pair 27 sample 1: V update complete for zero-base family.
    move.w  d0,d7                          ; Pair 27 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 27 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 27 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 27 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 27 sample 2: advance integer U without fractional carry.
    add.w   d5,d2                          ; Pair 27 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vb02_27_fast_b0u0p8               ; Pair 27 sample 2: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 27 sample 2: advance one wrapped texture row after V carry.
.vb02_27_fast_b0u0p8:                        ; Pair 27 sample 2: V update complete for zero-base family.
    or.l    (a1,a2.w),d7                  ; Pair 27: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 27: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 27: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 27: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 27: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 27: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 27: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 27: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 28 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 28 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 28 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 28 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 28 sample 1: advance integer U without fractional carry.
    add.w   d5,d2                          ; Pair 28 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vb01_28_fast_b0u0p8               ; Pair 28 sample 1: skip row carry when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 28 sample 1: advance one wrapped texture row after V carry.
.vb01_28_fast_b0u0p8:                        ; Pair 28 sample 1: V update complete for zero-base family.
    move.w  d0,d7                          ; Pair 28 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 28 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 28 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 28 sample 2: fetch the low-nibble contribution into d7.
    ;                                      ; Pair 28 sample 2: skip the final accumulator update; post-row delta includes it.
    or.l    (a1,a2.w),d7                  ; Pair 28: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 28: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 28: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 28: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 28: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 28: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 28: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 28: store plane 1 byte and advance plane 1.
    swap    d5                             ; Move the row count into the low word for DBRA.
    dbra    d5,.fast_b0u0p8_loop               ; Render the next logical row until all rows are complete.
    lea     STACK_TEMP_BYTES(sp),sp        ; Discard the temporary row-prefix and post-row stack slots.
    movem.l (sp)+,d2-d7/a2-a6              ; Restore all preserved registers.
    rts                                    ; Return to the C main loop without an extra final branch.

_RenderFastBm1U0P8Entry::                    ; Family entry for minus-one integer V row base and integrated pair 08.
    bra.s   .fast_bm1_after_swap           ; Enter the first row without applying the post-row delta.
.fast_bm1_loop:                          ; Start of the next logical row after DBRA branched.
    swap    d5                             ; Restore row count to the high word and V step to the low word.
.fast_bm1_post_row:                      ; Advance the rolling U/V seed from the previous row end to this row prefix.
    add.b   STACK_POST_DUL_BYTE(sp),d2     ; Apply the post-row fractional U delta and set X for the integer carry.
    move.w  STACK_POST_DUC(sp),d7          ; Load the post-row integer U delta into scratch register d7.
    addx.w  d7,d0                          ; Apply the post-row integer U delta plus the fractional carry.
    add.w   STACK_POST_VBASE(sp),d1        ; Apply the signed V row-base delta in texture-byte units.
    add.w   STACK_POST_VREM(sp),d2         ; Apply the post-row V fractional delta and set carry on row crossing.
    bcc.s   .fast_bm1_post_no_vcarry       ; Skip the extra V row increment when the post-row fraction did not wrap.
    addi.w  #$0200,d1                      ; Apply the extra V row increment produced by the post-row fractional carry.
.fast_bm1_post_no_vcarry:                ; Post-row V carry handling is complete.
.fast_bm1_after_swap:                    ; Row setup with the rolling seed already prepared for this row.
    movea.l (sp),a2            ; Reload the current row-prefix pointer from the stack slot.

    move.l  (a2)+,(a5)+                    ; Copy prefix pairs 01-04 directly from row state to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix pairs 01-04 directly from row state to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix pairs 01-04 directly from row state to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix pairs 01-04 directly from row state to plane 3.

.fast_bm1_pair05_06_prefix:              ; Emit prefix pairs 05-06 as direct plane words.
    move.w  (a2)+,(a5)+                    ; Pairs 05-06: copy the two premerged plane 0 bytes and advance plane 0.
    move.w  (a2)+,(a4)+                    ; Pairs 05-06: copy the two premerged plane 1 bytes and advance plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 05-06: copy the two premerged plane 2 bytes and advance plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 05-06: copy the two premerged plane 3 bytes and advance plane 3.

.fast_bm1_pair07_08_prefix:            ; Emit integrated prefix pairs 07-08 as direct plane words.
    move.w  (a2)+,(a5)+                    ; Pairs 07-08: copy the two premerged plane 0 bytes and advance plane 0.
    move.w  (a2)+,(a4)+                    ; Pairs 07-08: copy the two premerged plane 1 bytes and advance plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 07-08: copy the two premerged plane 2 bytes and advance plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 07-08: copy the two premerged plane 3 bytes and advance plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 09-10: copy packed word to plane 0 (high byte = pair 09, low byte = pair 10).
    move.w  (a2)+,(a4)+                    ; Pairs 09-10: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 09-10: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 09-10: copy packed word to plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 11-12: copy packed word to plane 0 (high byte = pair 11, low byte = pair 12).
    move.w  (a2)+,(a4)+                    ; Pairs 11-12: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 11-12: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 11-12: copy packed word to plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 13-14: copy packed word to plane 0 (high byte = pair 13, low byte = pair 14).
    move.w  (a2)+,(a4)+                    ; Pairs 13-14: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 13-14: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 13-14: copy packed word to plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 15: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 15: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 15: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 15: copy precomputed plane 3 byte and advance plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 16: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 16: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 16: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 16: copy precomputed plane 3 byte and advance plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 17: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 17: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 17: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 17: copy precomputed plane 3 byte and advance plane 3.
    move.l  a2,(sp)            ; Store the next row-prefix pointer after the integrated pair 17 bytes.

    move.w  d0,d7                          ; Pair 18 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 18 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 18 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 18 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 18 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm11_18_fast_bm1             ; Pair 18 sample 1: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 18 sample 1: decrement one wrapped texture row without carry.
.vbm11_18_fast_bm1:                      ; Pair 18 sample 1: V update complete for minus-one family.
    move.w  d0,d7                          ; Pair 18 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 18 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 18 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 18 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 18 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm12_18_fast_bm1             ; Pair 18 sample 2: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 18 sample 2: decrement one wrapped texture row without carry.
.vbm12_18_fast_bm1:                      ; Pair 18 sample 2: V update complete for minus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 18: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 18: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 18: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 18: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 18: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 18: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 18: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 18: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 19 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 19 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 19 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 19 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 19 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm11_19_fast_bm1             ; Pair 19 sample 1: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 19 sample 1: decrement one wrapped texture row without carry.
.vbm11_19_fast_bm1:                      ; Pair 19 sample 1: V update complete for minus-one family.
    move.w  d0,d7                          ; Pair 19 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 19 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 19 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 19 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 19 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm12_19_fast_bm1             ; Pair 19 sample 2: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 19 sample 2: decrement one wrapped texture row without carry.
.vbm12_19_fast_bm1:                      ; Pair 19 sample 2: V update complete for minus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 19: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 19: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 19: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 19: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 19: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 19: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 19: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 19: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 20 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 20 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 20 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 20 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 20 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm11_20_fast_bm1             ; Pair 20 sample 1: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 20 sample 1: decrement one wrapped texture row without carry.
.vbm11_20_fast_bm1:                      ; Pair 20 sample 1: V update complete for minus-one family.
    move.w  d0,d7                          ; Pair 20 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 20 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 20 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 20 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 20 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm12_20_fast_bm1             ; Pair 20 sample 2: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 20 sample 2: decrement one wrapped texture row without carry.
.vbm12_20_fast_bm1:                      ; Pair 20 sample 2: V update complete for minus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 20: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 20: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 20: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 20: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 20: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 20: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 20: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 20: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 21 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 21 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 21 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 21 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 21 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm11_21_fast_bm1             ; Pair 21 sample 1: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 21 sample 1: decrement one wrapped texture row without carry.
.vbm11_21_fast_bm1:                      ; Pair 21 sample 1: V update complete for minus-one family.
    move.w  d0,d7                          ; Pair 21 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 21 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 21 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 21 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 21 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm12_21_fast_bm1             ; Pair 21 sample 2: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 21 sample 2: decrement one wrapped texture row without carry.
.vbm12_21_fast_bm1:                      ; Pair 21 sample 2: V update complete for minus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 21: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 21: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 21: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 21: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 21: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 21: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 21: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 21: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 22 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 22 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 22 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 22 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 22 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm11_22_fast_bm1             ; Pair 22 sample 1: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 22 sample 1: decrement one wrapped texture row without carry.
.vbm11_22_fast_bm1:                      ; Pair 22 sample 1: V update complete for minus-one family.
    move.w  d0,d7                          ; Pair 22 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 22 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 22 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 22 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 22 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm12_22_fast_bm1             ; Pair 22 sample 2: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 22 sample 2: decrement one wrapped texture row without carry.
.vbm12_22_fast_bm1:                      ; Pair 22 sample 2: V update complete for minus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 22: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 22: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 22: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 22: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 22: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 22: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 22: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 22: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 23 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 23 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 23 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 23 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 23 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm11_23_fast_bm1             ; Pair 23 sample 1: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 23 sample 1: decrement one wrapped texture row without carry.
.vbm11_23_fast_bm1:                      ; Pair 23 sample 1: V update complete for minus-one family.
    move.w  d0,d7                          ; Pair 23 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 23 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 23 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 23 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 23 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm12_23_fast_bm1             ; Pair 23 sample 2: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 23 sample 2: decrement one wrapped texture row without carry.
.vbm12_23_fast_bm1:                      ; Pair 23 sample 2: V update complete for minus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 23: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 23: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 23: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 23: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 23: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 23: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 23: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 23: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 24 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 24 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 24 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 24 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 24 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm11_24_fast_bm1             ; Pair 24 sample 1: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 24 sample 1: decrement one wrapped texture row without carry.
.vbm11_24_fast_bm1:                      ; Pair 24 sample 1: V update complete for minus-one family.
    move.w  d0,d7                          ; Pair 24 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 24 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 24 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 24 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 24 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm12_24_fast_bm1             ; Pair 24 sample 2: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 24 sample 2: decrement one wrapped texture row without carry.
.vbm12_24_fast_bm1:                      ; Pair 24 sample 2: V update complete for minus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 24: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 24: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 24: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 24: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 24: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 24: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 24: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 24: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 25 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 25 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 25 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 25 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 25 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm11_25_fast_bm1             ; Pair 25 sample 1: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 25 sample 1: decrement one wrapped texture row without carry.
.vbm11_25_fast_bm1:                      ; Pair 25 sample 1: V update complete for minus-one family.
    move.w  d0,d7                          ; Pair 25 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 25 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 25 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 25 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 25 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm12_25_fast_bm1             ; Pair 25 sample 2: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 25 sample 2: decrement one wrapped texture row without carry.
.vbm12_25_fast_bm1:                      ; Pair 25 sample 2: V update complete for minus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 25: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 25: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 25: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 25: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 25: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 25: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 25: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 25: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 26 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 26 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 26 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 26 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Advance integer U (DuL is zero, no fractional carry).
    add.w   d5,d2                          ; Pair 26 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm11_26_fast_bm1             ; Pair 26 sample 1: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 26 sample 1: decrement one wrapped texture row without carry.
.vbm11_26_fast_bm1:                      ; Pair 26 sample 1: V update complete for minus-one family.
    move.w  d0,d7                          ; Pair 26 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 26 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 26 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 26 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 26 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 26 sample 2: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 26 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm12_26_fast_bm1             ; Pair 26 sample 2: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 26 sample 2: decrement one wrapped texture row without carry.
.vbm12_26_fast_bm1:                      ; Pair 26 sample 2: V update complete for minus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 26: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 26: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 26: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 26: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 26: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 26: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 26: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 26: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 27 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 27 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 27 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 27 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 27 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 27 sample 1: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 27 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm11_27_fast_bm1             ; Pair 27 sample 1: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 27 sample 1: decrement one wrapped texture row without carry.
.vbm11_27_fast_bm1:                      ; Pair 27 sample 1: V update complete for minus-one family.
    move.w  d0,d7                          ; Pair 27 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 27 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 27 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 27 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 27 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 27 sample 2: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 27 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm12_27_fast_bm1             ; Pair 27 sample 2: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 27 sample 2: decrement one wrapped texture row without carry.
.vbm12_27_fast_bm1:                      ; Pair 27 sample 2: V update complete for minus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 27: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 27: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 27: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 27: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 27: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 27: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 27: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 27: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 28 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 28 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 28 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 28 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 28 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 28 sample 1: advance integer U with the fractional carry.
    add.w   d5,d2                          ; Pair 28 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm11_28_fast_bm1             ; Pair 28 sample 1: skip row decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 28 sample 1: decrement one wrapped texture row without carry.
.vbm11_28_fast_bm1:                      ; Pair 28 sample 1: V update complete for minus-one family.
    move.w  d0,d7                          ; Pair 28 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 28 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 28 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 28 sample 2: fetch the low-nibble contribution into d7.
    ;                                      ; Pair 28 sample 2: skip the final accumulator update; post-row delta includes it.
    or.l    (a1,a2.w),d7                  ; Pair 28: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 28: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 28: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 28: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 28: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 28: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 28: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 28: store plane 1 byte and advance plane 1.
    swap    d5                             ; Move the row count into the low word for DBRA.
    dbra    d5,.fast_bm1_loop              ; Render the next logical row until all rows are complete.
    lea     STACK_TEMP_BYTES(sp),sp        ; Discard the temporary row-prefix and post-row stack slots.
    movem.l (sp)+,d2-d7/a2-a6              ; Restore all preserved registers.
    rts                                    ; Return to the C main loop without an extra final branch.

_RenderFastBp1P8Entry::                  ; Family entry for plus-one integer V row base and integrated pair 08.
    bra.s   .fast_bp1p8_after_swap         ; Enter the first row without applying the post-row delta.
.fast_bp1p8_loop:                        ; Start of the next logical row after DBRA branched.
    swap    d5                             ; Restore row count to the high word and V step to the low word.
.fast_bp1p8_post_row:                    ; Advance the rolling U/V seed from the previous row end to this row prefix.
    add.b   STACK_POST_DUL_BYTE(sp),d2     ; Apply the post-row fractional U delta and set X for the integer carry.
    move.w  STACK_POST_DUC(sp),d7          ; Load the post-row integer U delta into scratch register d7.
    addx.w  d7,d0                          ; Apply the post-row integer U delta plus the fractional carry.
    add.w   STACK_POST_VBASE(sp),d1        ; Apply the signed V row-base delta in texture-byte units.
    add.w   STACK_POST_VREM(sp),d2         ; Apply the post-row V fractional delta and set carry on row crossing.
    bcc.s   .fast_bp1p8_post_no_vcarry     ; Skip the extra V row increment when the post-row fraction did not wrap.
    addi.w  #$0200,d1                      ; Apply the extra V row increment produced by the post-row fractional carry.
.fast_bp1p8_post_no_vcarry:              ; Post-row V carry handling is complete.
.fast_bp1p8_after_swap:                  ; Row setup with the rolling seed already prepared for this row.
    movea.l (sp),a2            ; Reload the current row-prefix pointer from the stack slot.

    move.l  (a2)+,(a5)+                    ; Copy prefix pairs 01-04 directly from row state to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix pairs 01-04 directly from row state to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix pairs 01-04 directly from row state to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix pairs 01-04 directly from row state to plane 3.

.fast_bp1p8_pair05_06_prefix:            ; Emit prefix pairs 05-06 as direct plane words.
    move.w  (a2)+,(a5)+                    ; Pairs 05-06: copy the two premerged plane 0 bytes and advance plane 0.
    move.w  (a2)+,(a4)+                    ; Pairs 05-06: copy the two premerged plane 1 bytes and advance plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 05-06: copy the two premerged plane 2 bytes and advance plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 05-06: copy the two premerged plane 3 bytes and advance plane 3.

.fast_bp1p8_pair07_08_prefix:            ; Emit integrated prefix pairs 07-08 as direct plane words.
    move.w  (a2)+,(a5)+                    ; Pairs 07-08: copy the two premerged plane 0 bytes and advance plane 0.
    move.w  (a2)+,(a4)+                    ; Pairs 07-08: copy the two premerged plane 1 bytes and advance plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 07-08: copy the two premerged plane 2 bytes and advance plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 07-08: copy the two premerged plane 3 bytes and advance plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 09-10: copy packed word to plane 0 (high byte = pair 09, low byte = pair 10).
    move.w  (a2)+,(a4)+                    ; Pairs 09-10: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 09-10: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 09-10: copy packed word to plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 11-12: copy packed word to plane 0 (high byte = pair 11, low byte = pair 12).
    move.w  (a2)+,(a4)+                    ; Pairs 11-12: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 11-12: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 11-12: copy packed word to plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 13-14: copy packed word to plane 0 (high byte = pair 13, low byte = pair 14).
    move.w  (a2)+,(a4)+                    ; Pairs 13-14: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 13-14: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 13-14: copy packed word to plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 15: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 15: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 15: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 15: copy precomputed plane 3 byte and advance plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 16: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 16: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 16: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 16: copy precomputed plane 3 byte and advance plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 17: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 17: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 17: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 17: copy precomputed plane 3 byte and advance plane 3.
    move.l  a2,(sp)            ; Store the next row-prefix pointer after the integrated pair 17 bytes.

    move.w  d0,d7                          ; Pair 18 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 18 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 18 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 18 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 18 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 18 sample 1: advance integer U with the fractional carry.
    addi.w  #$0200,d1                      ; Pair 18 sample 1: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 18 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vbp01_18_fast_bp1p8           ; Pair 18 sample 1: skip the extra row step when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 18 sample 1: add the fractional carry texture row step.
.vbp01_18_fast_bp1p8:                    ; Pair 18 sample 1: V update complete for plus-one family.
    move.w  d0,d7                          ; Pair 18 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 18 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 18 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 18 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 18 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 18 sample 2: advance integer U with the fractional carry.
    addi.w  #$0200,d1                      ; Pair 18 sample 2: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 18 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vbp02_18_fast_bp1p8           ; Pair 18 sample 2: skip the extra row step when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 18 sample 2: add the fractional carry texture row step.
.vbp02_18_fast_bp1p8:                    ; Pair 18 sample 2: V update complete for plus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 18: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 18: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 18: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 18: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 18: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 18: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 18: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 18: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 19 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 19 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 19 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 19 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 19 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 19 sample 1: advance integer U with the fractional carry.
    addi.w  #$0200,d1                      ; Pair 19 sample 1: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 19 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vbp01_19_fast_bp1p8           ; Pair 19 sample 1: skip the extra row step when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 19 sample 1: add the fractional carry texture row step.
.vbp01_19_fast_bp1p8:                    ; Pair 19 sample 1: V update complete for plus-one family.
    move.w  d0,d7                          ; Pair 19 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 19 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 19 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 19 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 19 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 19 sample 2: advance integer U with the fractional carry.
    addi.w  #$0200,d1                      ; Pair 19 sample 2: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 19 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vbp02_19_fast_bp1p8           ; Pair 19 sample 2: skip the extra row step when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 19 sample 2: add the fractional carry texture row step.
.vbp02_19_fast_bp1p8:                    ; Pair 19 sample 2: V update complete for plus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 19: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 19: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 19: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 19: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 19: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 19: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 19: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 19: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 20 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 20 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 20 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 20 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 20 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 20 sample 1: advance integer U with the fractional carry.
    addi.w  #$0200,d1                      ; Pair 20 sample 1: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 20 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vbp01_20_fast_bp1p8           ; Pair 20 sample 1: skip the extra row step when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 20 sample 1: add the fractional carry texture row step.
.vbp01_20_fast_bp1p8:                    ; Pair 20 sample 1: V update complete for plus-one family.
    move.w  d0,d7                          ; Pair 20 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 20 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 20 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 20 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 20 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 20 sample 2: advance integer U with the fractional carry.
    addi.w  #$0200,d1                      ; Pair 20 sample 2: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 20 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vbp02_20_fast_bp1p8           ; Pair 20 sample 2: skip the extra row step when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 20 sample 2: add the fractional carry texture row step.
.vbp02_20_fast_bp1p8:                    ; Pair 20 sample 2: V update complete for plus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 20: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 20: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 20: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 20: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 20: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 20: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 20: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 20: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 21 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 21 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 21 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 21 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 21 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 21 sample 1: advance integer U with the fractional carry.
    addi.w  #$0200,d1                      ; Pair 21 sample 1: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 21 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vbp01_21_fast_bp1p8           ; Pair 21 sample 1: skip the extra row step when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 21 sample 1: add the fractional carry texture row step.
.vbp01_21_fast_bp1p8:                    ; Pair 21 sample 1: V update complete for plus-one family.
    move.w  d0,d7                          ; Pair 21 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 21 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 21 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 21 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 21 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 21 sample 2: advance integer U with the fractional carry.
    addi.w  #$0200,d1                      ; Pair 21 sample 2: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 21 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vbp02_21_fast_bp1p8           ; Pair 21 sample 2: skip the extra row step when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 21 sample 2: add the fractional carry texture row step.
.vbp02_21_fast_bp1p8:                    ; Pair 21 sample 2: V update complete for plus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 21: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 21: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 21: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 21: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 21: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 21: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 21: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 21: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 22 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 22 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 22 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 22 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 22 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 22 sample 1: advance integer U with the fractional carry.
    addi.w  #$0200,d1                      ; Pair 22 sample 1: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 22 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vbp01_22_fast_bp1p8           ; Pair 22 sample 1: skip the extra row step when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 22 sample 1: add the fractional carry texture row step.
.vbp01_22_fast_bp1p8:                    ; Pair 22 sample 1: V update complete for plus-one family.
    move.w  d0,d7                          ; Pair 22 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 22 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 22 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 22 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 22 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 22 sample 2: advance integer U with the fractional carry.
    addi.w  #$0200,d1                      ; Pair 22 sample 2: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 22 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vbp02_22_fast_bp1p8           ; Pair 22 sample 2: skip the extra row step when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 22 sample 2: add the fractional carry texture row step.
.vbp02_22_fast_bp1p8:                    ; Pair 22 sample 2: V update complete for plus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 22: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 22: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 22: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 22: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 22: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 22: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 22: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 22: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 23 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 23 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 23 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 23 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 23 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 23 sample 1: advance integer U with the fractional carry.
    addi.w  #$0200,d1                      ; Pair 23 sample 1: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 23 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vbp01_23_fast_bp1p8           ; Pair 23 sample 1: skip the extra row step when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 23 sample 1: add the fractional carry texture row step.
.vbp01_23_fast_bp1p8:                    ; Pair 23 sample 1: V update complete for plus-one family.
    move.w  d0,d7                          ; Pair 23 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 23 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 23 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 23 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 23 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 23 sample 2: advance integer U with the fractional carry.
    addi.w  #$0200,d1                      ; Pair 23 sample 2: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 23 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vbp02_23_fast_bp1p8           ; Pair 23 sample 2: skip the extra row step when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 23 sample 2: add the fractional carry texture row step.
.vbp02_23_fast_bp1p8:                    ; Pair 23 sample 2: V update complete for plus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 23: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 23: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 23: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 23: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 23: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 23: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 23: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 23: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 24 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 24 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 24 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 24 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 24 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 24 sample 1: advance integer U with the fractional carry.
    addi.w  #$0200,d1                      ; Pair 24 sample 1: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 24 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vbp01_24_fast_bp1p8           ; Pair 24 sample 1: skip the extra row step when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 24 sample 1: add the fractional carry texture row step.
.vbp01_24_fast_bp1p8:                    ; Pair 24 sample 1: V update complete for plus-one family.
    move.w  d0,d7                          ; Pair 24 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 24 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 24 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 24 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 24 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 24 sample 2: advance integer U with the fractional carry.
    addi.w  #$0200,d1                      ; Pair 24 sample 2: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 24 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vbp02_24_fast_bp1p8           ; Pair 24 sample 2: skip the extra row step when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 24 sample 2: add the fractional carry texture row step.
.vbp02_24_fast_bp1p8:                    ; Pair 24 sample 2: V update complete for plus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 24: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 24: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 24: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 24: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 24: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 24: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 24: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 24: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 25 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 25 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 25 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 25 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 25 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 25 sample 1: advance integer U with the fractional carry.
    addi.w  #$0200,d1                      ; Pair 25 sample 1: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 25 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vbp01_25_fast_bp1p8           ; Pair 25 sample 1: skip the extra row step when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 25 sample 1: add the fractional carry texture row step.
.vbp01_25_fast_bp1p8:                    ; Pair 25 sample 1: V update complete for plus-one family.
    move.w  d0,d7                          ; Pair 25 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 25 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 25 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 25 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 25 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 25 sample 2: advance integer U with the fractional carry.
    addi.w  #$0200,d1                      ; Pair 25 sample 2: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 25 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vbp02_25_fast_bp1p8           ; Pair 25 sample 2: skip the extra row step when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 25 sample 2: add the fractional carry texture row step.
.vbp02_25_fast_bp1p8:                    ; Pair 25 sample 2: V update complete for plus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 25: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 25: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 25: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 25: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 25: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 25: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 25: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 25: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 26 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 26 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 26 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 26 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 26 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 26 sample 1: advance integer U with the fractional carry.
    addi.w  #$0200,d1                      ; Pair 26 sample 1: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 26 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vbp01_26_fast_bp1p8           ; Pair 26 sample 1: skip the extra row step when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 26 sample 1: add the fractional carry texture row step.
.vbp01_26_fast_bp1p8:                    ; Pair 26 sample 1: V update complete for plus-one family.
    move.w  d0,d7                          ; Pair 26 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 26 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 26 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 26 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 26 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 26 sample 2: advance integer U with the fractional carry.
    addi.w  #$0200,d1                      ; Pair 26 sample 2: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 26 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vbp12_26_fast_bp1p8             ; Pair 26 sample 2: skip the extra row step when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 26 sample 2: advance one wrapped texture row after V carry.
.vbp12_26_fast_bp1p8:                      ; Pair 26 sample 2: V update complete for plus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 26: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 26: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 26: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 26: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 26: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 26: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 26: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 26: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 27 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 27 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 27 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 27 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 27 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 27 sample 1: advance integer U with the fractional carry.
    addi.w  #$0200,d1                      ; Pair 27 sample 1: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 27 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vbp11_27_fast_bp1p8             ; Pair 27 sample 1: skip the extra row step when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 27 sample 1: advance one wrapped texture row after V carry.
.vbp11_27_fast_bp1p8:                      ; Pair 27 sample 1: V update complete for plus-one family.
    move.w  d0,d7                          ; Pair 27 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 27 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 27 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 27 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 27 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 27 sample 2: advance integer U with the fractional carry.
    addi.w  #$0200,d1                      ; Pair 27 sample 2: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 27 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vbp12_27_fast_bp1p8             ; Pair 27 sample 2: skip the extra row step when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 27 sample 2: advance one wrapped texture row after V carry.
.vbp12_27_fast_bp1p8:                      ; Pair 27 sample 2: V update complete for plus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 27: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 27: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 27: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 27: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 27: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 27: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 27: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 27: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 28 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 28 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 28 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 28 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 28 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 28 sample 1: advance integer U with the fractional carry.
    addi.w  #$0200,d1                      ; Pair 28 sample 1: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 28 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vbp11_28_fast_bp1p8             ; Pair 28 sample 1: skip the extra row step when the V fraction did not wrap.
    addi.w  #$0200,d1                      ; Pair 28 sample 1: advance one wrapped texture row after V carry.
.vbp11_28_fast_bp1p8:                      ; Pair 28 sample 1: V update complete for plus-one family.
    move.w  d0,d7                          ; Pair 28 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 28 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 28 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 28 sample 2: fetch the low-nibble contribution into d7.
    ;                                      ; Pair 28 sample 2: skip the final accumulator update; post-row delta includes it.
    or.l    (a1,a2.w),d7                  ; Pair 28: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 28: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 28: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 28: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 28: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 28: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 28: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 28: store plane 1 byte and advance plane 1.
    swap    d5                             ; Move the row count into the low word for DBRA.
    dbra    d5,.fast_bp1p8_loop            ; Render the next logical row until all rows are complete.
    lea     STACK_TEMP_BYTES(sp),sp        ; Discard the temporary row-prefix and post-row stack slots.
    movem.l (sp)+,d2-d7/a2-a6              ; Restore all preserved registers.
    rts                                    ; Return to the C main loop without an extra final branch.

_RenderFastBm2P8Entry::                  ; Family entry for minus-two integer V row base and integrated pair 08.
    bra.s   .fast_bm2p8_after_swap         ; Enter the first row without applying the post-row delta.
.fast_bm2p8_loop:                        ; Start of the next logical row after DBRA branched.
    swap    d5                             ; Restore row count to the high word and V step to the low word.
.fast_bm2p8_post_row:                    ; Advance the rolling U/V seed from the previous row end to this row prefix.
    add.b   STACK_POST_DUL_BYTE(sp),d2     ; Apply the post-row fractional U delta and set X for the integer carry.
    move.w  STACK_POST_DUC(sp),d7          ; Load the post-row integer U delta into scratch register d7.
    addx.w  d7,d0                          ; Apply the post-row integer U delta plus the fractional carry.
    add.w   STACK_POST_VBASE(sp),d1        ; Apply the signed V row-base delta in texture-byte units.
    add.w   STACK_POST_VREM(sp),d2         ; Apply the post-row V fractional delta and set carry on row crossing.
    bcc.s   .fast_bm2p8_post_no_vcarry     ; Skip the extra V row increment when the post-row fraction did not wrap.
    addi.w  #$0200,d1                      ; Apply the extra V row increment produced by the post-row fractional carry.
.fast_bm2p8_post_no_vcarry:              ; Post-row V carry handling is complete.
.fast_bm2p8_after_swap:                  ; Row setup with the rolling seed already prepared for this row.
    movea.l (sp),a2            ; Reload the current row-prefix pointer from the stack slot.

    move.l  (a2)+,(a5)+                    ; Copy prefix pairs 01-04 directly from row state to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix pairs 01-04 directly from row state to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix pairs 01-04 directly from row state to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix pairs 01-04 directly from row state to plane 3.

.fast_bm2p8_pair05_06_prefix:            ; Emit prefix pairs 05-06 as direct plane words.
    move.w  (a2)+,(a5)+                    ; Pairs 05-06: copy the two premerged plane 0 bytes and advance plane 0.
    move.w  (a2)+,(a4)+                    ; Pairs 05-06: copy the two premerged plane 1 bytes and advance plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 05-06: copy the two premerged plane 2 bytes and advance plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 05-06: copy the two premerged plane 3 bytes and advance plane 3.

.fast_bm2p8_pair07_08_prefix:            ; Emit integrated prefix pairs 07-08 as direct plane words.
    move.w  (a2)+,(a5)+                    ; Pairs 07-08: copy the two premerged plane 0 bytes and advance plane 0.
    move.w  (a2)+,(a4)+                    ; Pairs 07-08: copy the two premerged plane 1 bytes and advance plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 07-08: copy the two premerged plane 2 bytes and advance plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 07-08: copy the two premerged plane 3 bytes and advance plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 09-10: copy packed word to plane 0 (high byte = pair 09, low byte = pair 10).
    move.w  (a2)+,(a4)+                    ; Pairs 09-10: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 09-10: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 09-10: copy packed word to plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 11-12: copy packed word to plane 0 (high byte = pair 11, low byte = pair 12).
    move.w  (a2)+,(a4)+                    ; Pairs 11-12: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 11-12: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 11-12: copy packed word to plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 13-14: copy packed word to plane 0 (high byte = pair 13, low byte = pair 14).
    move.w  (a2)+,(a4)+                    ; Pairs 13-14: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 13-14: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 13-14: copy packed word to plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 15: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 15: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 15: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 15: copy precomputed plane 3 byte and advance plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 16: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 16: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 16: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 16: copy precomputed plane 3 byte and advance plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 17: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 17: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 17: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 17: copy precomputed plane 3 byte and advance plane 3.
    move.l  a2,(sp)            ; Store the next row-prefix pointer after the integrated pair 17 bytes.

    move.w  d0,d7                          ; Pair 18 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 18 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 18 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 18 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 18 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 18 sample 1: advance integer U with the fractional carry.
    subi.w  #$0200,d1                      ; Pair 18 sample 1: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 18 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm21_18_fast_bm2p8           ; Pair 18 sample 1: skip the extra decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 18 sample 1: apply the second row decrement without carry.
.vbm21_18_fast_bm2p8:                    ; Pair 18 sample 1: V update complete for minus-two family.
    move.w  d0,d7                          ; Pair 18 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 18 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 18 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 18 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 18 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 18 sample 2: advance integer U with the fractional carry.
    subi.w  #$0200,d1                      ; Pair 18 sample 2: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 18 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm22_18_fast_bm2p8           ; Pair 18 sample 2: skip the extra decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 18 sample 2: apply the second row decrement without carry.
.vbm22_18_fast_bm2p8:                    ; Pair 18 sample 2: V update complete for minus-two family.
    or.l    (a1,a2.w),d7                  ; Pair 18: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 18: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 18: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 18: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 18: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 18: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 18: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 18: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 19 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 19 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 19 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 19 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 19 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 19 sample 1: advance integer U with the fractional carry.
    subi.w  #$0200,d1                      ; Pair 19 sample 1: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 19 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm21_19_fast_bm2p8           ; Pair 19 sample 1: skip the extra decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 19 sample 1: apply the second row decrement without carry.
.vbm21_19_fast_bm2p8:                    ; Pair 19 sample 1: V update complete for minus-two family.
    move.w  d0,d7                          ; Pair 19 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 19 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 19 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 19 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 19 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 19 sample 2: advance integer U with the fractional carry.
    subi.w  #$0200,d1                      ; Pair 19 sample 2: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 19 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm22_19_fast_bm2p8           ; Pair 19 sample 2: skip the extra decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 19 sample 2: apply the second row decrement without carry.
.vbm22_19_fast_bm2p8:                    ; Pair 19 sample 2: V update complete for minus-two family.
    or.l    (a1,a2.w),d7                  ; Pair 19: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 19: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 19: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 19: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 19: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 19: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 19: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 19: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 20 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 20 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 20 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 20 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 20 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 20 sample 1: advance integer U with the fractional carry.
    subi.w  #$0200,d1                      ; Pair 20 sample 1: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 20 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm21_20_fast_bm2p8           ; Pair 20 sample 1: skip the extra decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 20 sample 1: apply the second row decrement without carry.
.vbm21_20_fast_bm2p8:                    ; Pair 20 sample 1: V update complete for minus-two family.
    move.w  d0,d7                          ; Pair 20 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 20 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 20 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 20 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 20 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 20 sample 2: advance integer U with the fractional carry.
    subi.w  #$0200,d1                      ; Pair 20 sample 2: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 20 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm22_20_fast_bm2p8           ; Pair 20 sample 2: skip the extra decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 20 sample 2: apply the second row decrement without carry.
.vbm22_20_fast_bm2p8:                    ; Pair 20 sample 2: V update complete for minus-two family.
    or.l    (a1,a2.w),d7                  ; Pair 20: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 20: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 20: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 20: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 20: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 20: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 20: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 20: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 21 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 21 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 21 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 21 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 21 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 21 sample 1: advance integer U with the fractional carry.
    subi.w  #$0200,d1                      ; Pair 21 sample 1: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 21 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm21_21_fast_bm2p8           ; Pair 21 sample 1: skip the extra decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 21 sample 1: apply the second row decrement without carry.
.vbm21_21_fast_bm2p8:                    ; Pair 21 sample 1: V update complete for minus-two family.
    move.w  d0,d7                          ; Pair 21 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 21 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 21 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 21 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 21 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 21 sample 2: advance integer U with the fractional carry.
    subi.w  #$0200,d1                      ; Pair 21 sample 2: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 21 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm22_21_fast_bm2p8           ; Pair 21 sample 2: skip the extra decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 21 sample 2: apply the second row decrement without carry.
.vbm22_21_fast_bm2p8:                    ; Pair 21 sample 2: V update complete for minus-two family.
    or.l    (a1,a2.w),d7                  ; Pair 21: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 21: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 21: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 21: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 21: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 21: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 21: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 21: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 22 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 22 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 22 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 22 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 22 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 22 sample 1: advance integer U with the fractional carry.
    subi.w  #$0200,d1                      ; Pair 22 sample 1: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 22 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm21_22_fast_bm2p8           ; Pair 22 sample 1: skip the extra decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 22 sample 1: apply the second row decrement without carry.
.vbm21_22_fast_bm2p8:                    ; Pair 22 sample 1: V update complete for minus-two family.
    move.w  d0,d7                          ; Pair 22 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 22 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 22 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 22 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 22 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 22 sample 2: advance integer U with the fractional carry.
    subi.w  #$0200,d1                      ; Pair 22 sample 2: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 22 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm22_22_fast_bm2p8           ; Pair 22 sample 2: skip the extra decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 22 sample 2: apply the second row decrement without carry.
.vbm22_22_fast_bm2p8:                    ; Pair 22 sample 2: V update complete for minus-two family.
    or.l    (a1,a2.w),d7                  ; Pair 22: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 22: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 22: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 22: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 22: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 22: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 22: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 22: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 23 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 23 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 23 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 23 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 23 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 23 sample 1: advance integer U with the fractional carry.
    subi.w  #$0200,d1                      ; Pair 23 sample 1: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 23 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm21_23_fast_bm2p8           ; Pair 23 sample 1: skip the extra decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 23 sample 1: apply the second row decrement without carry.
.vbm21_23_fast_bm2p8:                    ; Pair 23 sample 1: V update complete for minus-two family.
    move.w  d0,d7                          ; Pair 23 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 23 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 23 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 23 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 23 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 23 sample 2: advance integer U with the fractional carry.
    subi.w  #$0200,d1                      ; Pair 23 sample 2: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 23 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm22_23_fast_bm2p8           ; Pair 23 sample 2: skip the extra decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 23 sample 2: apply the second row decrement without carry.
.vbm22_23_fast_bm2p8:                    ; Pair 23 sample 2: V update complete for minus-two family.
    or.l    (a1,a2.w),d7                  ; Pair 23: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 23: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 23: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 23: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 23: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 23: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 23: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 23: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 24 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 24 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 24 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 24 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 24 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 24 sample 1: advance integer U with the fractional carry.
    subi.w  #$0200,d1                      ; Pair 24 sample 1: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 24 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm21_24_fast_bm2p8           ; Pair 24 sample 1: skip the extra decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 24 sample 1: apply the second row decrement without carry.
.vbm21_24_fast_bm2p8:                    ; Pair 24 sample 1: V update complete for minus-two family.
    move.w  d0,d7                          ; Pair 24 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 24 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 24 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 24 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 24 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 24 sample 2: advance integer U with the fractional carry.
    subi.w  #$0200,d1                      ; Pair 24 sample 2: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 24 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm22_24_fast_bm2p8           ; Pair 24 sample 2: skip the extra decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 24 sample 2: apply the second row decrement without carry.
.vbm22_24_fast_bm2p8:                    ; Pair 24 sample 2: V update complete for minus-two family.
    or.l    (a1,a2.w),d7                  ; Pair 24: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 24: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 24: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 24: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 24: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 24: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 24: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 24: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 25 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 25 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 25 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 25 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 25 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 25 sample 1: advance integer U with the fractional carry.
    subi.w  #$0200,d1                      ; Pair 25 sample 1: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 25 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm21_25_fast_bm2p8           ; Pair 25 sample 1: skip the extra decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 25 sample 1: apply the second row decrement without carry.
.vbm21_25_fast_bm2p8:                    ; Pair 25 sample 1: V update complete for minus-two family.
    move.w  d0,d7                          ; Pair 25 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 25 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 25 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 25 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 25 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 25 sample 2: advance integer U with the fractional carry.
    subi.w  #$0200,d1                      ; Pair 25 sample 2: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 25 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm22_25_fast_bm2p8           ; Pair 25 sample 2: skip the extra decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 25 sample 2: apply the second row decrement without carry.
.vbm22_25_fast_bm2p8:                    ; Pair 25 sample 2: V update complete for minus-two family.
    or.l    (a1,a2.w),d7                  ; Pair 25: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 25: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 25: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 25: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 25: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 25: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 25: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 25: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 26 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 26 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 26 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 26 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 26 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 26 sample 1: advance integer U with the fractional carry.
    subi.w  #$0200,d1                      ; Pair 26 sample 1: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 26 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm21_26_fast_bm2p8           ; Pair 26 sample 1: skip the extra decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 26 sample 1: apply the second row decrement without carry.
.vbm21_26_fast_bm2p8:                    ; Pair 26 sample 1: V update complete for minus-two family.
    move.w  d0,d7                          ; Pair 26 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 26 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 26 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 26 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 26 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 26 sample 2: advance integer U with the fractional carry.
    subi.w  #$0200,d1                      ; Pair 26 sample 2: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 26 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm22_26_fast_bm2p8             ; Pair 26 sample 2: skip the extra decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 26 sample 2: decrement two wrapped texture rows without carry.
.vbm22_26_fast_bm2p8:                      ; Pair 26 sample 2: V update complete for minus-two family.
    or.l    (a1,a2.w),d7                  ; Pair 26: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 26: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 26: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 26: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 26: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 26: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 26: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 26: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 27 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 27 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 27 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 27 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 27 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 27 sample 1: advance integer U with the fractional carry.
    subi.w  #$0200,d1                      ; Pair 27 sample 1: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 27 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm21_27_fast_bm2p8             ; Pair 27 sample 1: skip the extra decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 27 sample 1: decrement two wrapped texture rows without carry.
.vbm21_27_fast_bm2p8:                      ; Pair 27 sample 1: V update complete for minus-two family.
    move.w  d0,d7                          ; Pair 27 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 27 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 27 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 27 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 27 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 27 sample 2: advance integer U with the fractional carry.
    subi.w  #$0200,d1                      ; Pair 27 sample 2: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 27 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm22_27_fast_bm2p8             ; Pair 27 sample 2: skip the extra decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 27 sample 2: decrement two wrapped texture rows without carry.
.vbm22_27_fast_bm2p8:                      ; Pair 27 sample 2: V update complete for minus-two family.
    or.l    (a1,a2.w),d7                  ; Pair 27: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 27: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 27: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 27: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 27: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 27: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 27: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 27: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 28 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 28 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 28 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 28 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 28 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 28 sample 1: advance integer U with the fractional carry.
    subi.w  #$0200,d1                      ; Pair 28 sample 1: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 28 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm21_28_fast_bm2p8             ; Pair 28 sample 1: skip the extra decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 28 sample 1: decrement two wrapped texture rows without carry.
.vbm21_28_fast_bm2p8:                      ; Pair 28 sample 1: V update complete for minus-two family.
    move.w  d0,d7                          ; Pair 28 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 28 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 28 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 28 sample 2: fetch the low-nibble contribution into d7.
    ;                                      ; Pair 28 sample 2: skip the final accumulator update; post-row delta includes it.
    or.l    (a1,a2.w),d7                  ; Pair 28: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 28: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 28: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 28: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 28: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 28: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 28: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 28: store plane 1 byte and advance plane 1.
    swap    d5                             ; Move the row count into the low word for DBRA.
    dbra    d5,.fast_bm2p8_loop            ; Render the next logical row until all rows are complete.
    lea     STACK_TEMP_BYTES(sp),sp        ; Discard the temporary row-prefix and post-row stack slots.
    movem.l (sp)+,d2-d7/a2-a6              ; Restore all preserved registers.
    rts                                    ; Return to the C main loop without an extra final branch.

_RenderFastBp1U0P8Entry::                ; Family entry for plus-one integer V row base and DuL equal to zero and integrated pair 08.
    move.w  #$0200,d4                      ; Reuse the unused U-fraction register as a one-texture-row quantum.
    bra.s   .fast_bp1u0p8_after_swap       ; Enter the first row without applying the post-row delta.
.fast_bp1u0p8_loop:                      ; Start of the next logical row after DBRA branched.
    swap    d5                             ; Restore row count to the high word and V step to the low word.
.fast_bp1u0p8_post_row:                  ; Advance the rolling U/V seed from the previous row end to this row prefix.
    add.b   STACK_POST_DUL_BYTE(sp),d2     ; Apply the post-row fractional U delta and set X for the integer carry.
    move.w  STACK_POST_DUC(sp),d7          ; Load the post-row integer U delta into scratch register d7.
    addx.w  d7,d0                          ; Apply the post-row integer U delta plus the fractional carry.
    add.w   STACK_POST_VBASE(sp),d1        ; Apply the signed V row-base delta in texture-byte units.
    add.w   STACK_POST_VREM(sp),d2         ; Apply the post-row V fractional delta and set carry on row crossing.
    bcc.s   .fast_bp1u0p8_post_no_vcarry   ; Skip the extra V row increment when the post-row fraction did not wrap.
    add.w   d4,d1                          ; Apply the extra V row increment produced by the post-row fractional carry.
.fast_bp1u0p8_post_no_vcarry:            ; Post-row V carry handling is complete.
.fast_bp1u0p8_after_swap:                ; Row setup with the rolling seed already prepared for this row.
    movea.l (sp),a2            ; Reload the current row-prefix pointer from the stack slot.

    move.l  (a2)+,(a5)+                    ; Copy prefix pairs 01-04 directly from row state to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix pairs 01-04 directly from row state to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix pairs 01-04 directly from row state to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix pairs 01-04 directly from row state to plane 3.

.fast_bp1u0p8_pair05_06_prefix:          ; Emit prefix pairs 05-06 as direct plane words.
    move.w  (a2)+,(a5)+                    ; Pairs 05-06: copy the two premerged plane 0 bytes and advance plane 0.
    move.w  (a2)+,(a4)+                    ; Pairs 05-06: copy the two premerged plane 1 bytes and advance plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 05-06: copy the two premerged plane 2 bytes and advance plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 05-06: copy the two premerged plane 3 bytes and advance plane 3.

.fast_bp1u0p8_pair07_08_prefix:            ; Emit integrated prefix pairs 07-08 as direct plane words.
    move.w  (a2)+,(a5)+                    ; Pairs 07-08: copy the two premerged plane 0 bytes and advance plane 0.
    move.w  (a2)+,(a4)+                    ; Pairs 07-08: copy the two premerged plane 1 bytes and advance plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 07-08: copy the two premerged plane 2 bytes and advance plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 07-08: copy the two premerged plane 3 bytes and advance plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 09-10: copy packed word to plane 0 (high byte = pair 09, low byte = pair 10).
    move.w  (a2)+,(a4)+                    ; Pairs 09-10: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 09-10: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 09-10: copy packed word to plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 11-12: copy packed word to plane 0 (high byte = pair 11, low byte = pair 12).
    move.w  (a2)+,(a4)+                    ; Pairs 11-12: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 11-12: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 11-12: copy packed word to plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 13-14: copy packed word to plane 0 (high byte = pair 13, low byte = pair 14).
    move.w  (a2)+,(a4)+                    ; Pairs 13-14: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 13-14: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 13-14: copy packed word to plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 15: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 15: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 15: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 15: copy precomputed plane 3 byte and advance plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 16: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 16: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 16: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 16: copy precomputed plane 3 byte and advance plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 17: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 17: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 17: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 17: copy precomputed plane 3 byte and advance plane 3.
    move.l  a2,(sp)            ; Store the next row-prefix pointer after the integrated pair 17 bytes.

    move.w  d0,d7                          ; Pair 18 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 18 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 18 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 18 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 18 sample 1: advance integer U without fractional carry.
    add.w   d4,d1                          ; Pair 18 sample 1: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 18 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vbp01_18_fast_bp1u0p8         ; Pair 18 sample 1: skip the extra row step when the V fraction did not wrap.
    add.w   d4,d1                          ; Pair 18 sample 1: add the fractional carry texture row step.
.vbp01_18_fast_bp1u0p8:                  ; Pair 18 sample 1: V update complete for plus-one family.
    move.w  d0,d7                          ; Pair 18 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 18 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 18 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 18 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 18 sample 2: advance integer U without fractional carry.
    add.w   d4,d1                          ; Pair 18 sample 2: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 18 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vbp02_18_fast_bp1u0p8         ; Pair 18 sample 2: skip the extra row step when the V fraction did not wrap.
    add.w   d4,d1                          ; Pair 18 sample 2: add the fractional carry texture row step.
.vbp02_18_fast_bp1u0p8:                  ; Pair 18 sample 2: V update complete for plus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 18: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 18: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 18: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 18: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 18: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 18: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 18: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 18: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 19 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 19 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 19 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 19 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 19 sample 1: advance integer U without fractional carry.
    add.w   d4,d1                          ; Pair 19 sample 1: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 19 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vbp01_19_fast_bp1u0p8         ; Pair 19 sample 1: skip the extra row step when the V fraction did not wrap.
    add.w   d4,d1                          ; Pair 19 sample 1: add the fractional carry texture row step.
.vbp01_19_fast_bp1u0p8:                  ; Pair 19 sample 1: V update complete for plus-one family.
    move.w  d0,d7                          ; Pair 19 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 19 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 19 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 19 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 19 sample 2: advance integer U without fractional carry.
    add.w   d4,d1                          ; Pair 19 sample 2: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 19 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vbp02_19_fast_bp1u0p8         ; Pair 19 sample 2: skip the extra row step when the V fraction did not wrap.
    add.w   d4,d1                          ; Pair 19 sample 2: add the fractional carry texture row step.
.vbp02_19_fast_bp1u0p8:                  ; Pair 19 sample 2: V update complete for plus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 19: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 19: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 19: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 19: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 19: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 19: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 19: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 19: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 20 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 20 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 20 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 20 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 20 sample 1: advance integer U without fractional carry.
    add.w   d4,d1                          ; Pair 20 sample 1: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 20 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vbp01_20_fast_bp1u0p8         ; Pair 20 sample 1: skip the extra row step when the V fraction did not wrap.
    add.w   d4,d1                          ; Pair 20 sample 1: add the fractional carry texture row step.
.vbp01_20_fast_bp1u0p8:                  ; Pair 20 sample 1: V update complete for plus-one family.
    move.w  d0,d7                          ; Pair 20 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 20 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 20 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 20 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 20 sample 2: advance integer U without fractional carry.
    add.w   d4,d1                          ; Pair 20 sample 2: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 20 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vbp02_20_fast_bp1u0p8         ; Pair 20 sample 2: skip the extra row step when the V fraction did not wrap.
    add.w   d4,d1                          ; Pair 20 sample 2: add the fractional carry texture row step.
.vbp02_20_fast_bp1u0p8:                  ; Pair 20 sample 2: V update complete for plus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 20: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 20: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 20: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 20: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 20: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 20: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 20: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 20: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 21 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 21 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 21 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 21 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 21 sample 1: advance integer U without fractional carry.
    add.w   d4,d1                          ; Pair 21 sample 1: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 21 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vbp01_21_fast_bp1u0p8         ; Pair 21 sample 1: skip the extra row step when the V fraction did not wrap.
    add.w   d4,d1                          ; Pair 21 sample 1: add the fractional carry texture row step.
.vbp01_21_fast_bp1u0p8:                  ; Pair 21 sample 1: V update complete for plus-one family.
    move.w  d0,d7                          ; Pair 21 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 21 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 21 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 21 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 21 sample 2: advance integer U without fractional carry.
    add.w   d4,d1                          ; Pair 21 sample 2: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 21 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vbp02_21_fast_bp1u0p8         ; Pair 21 sample 2: skip the extra row step when the V fraction did not wrap.
    add.w   d4,d1                          ; Pair 21 sample 2: add the fractional carry texture row step.
.vbp02_21_fast_bp1u0p8:                  ; Pair 21 sample 2: V update complete for plus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 21: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 21: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 21: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 21: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 21: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 21: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 21: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 21: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 22 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 22 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 22 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 22 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 22 sample 1: advance integer U without fractional carry.
    add.w   d4,d1                          ; Pair 22 sample 1: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 22 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vbp01_22_fast_bp1u0p8         ; Pair 22 sample 1: skip the extra row step when the V fraction did not wrap.
    add.w   d4,d1                          ; Pair 22 sample 1: add the fractional carry texture row step.
.vbp01_22_fast_bp1u0p8:                  ; Pair 22 sample 1: V update complete for plus-one family.
    move.w  d0,d7                          ; Pair 22 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 22 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 22 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 22 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 22 sample 2: advance integer U without fractional carry.
    add.w   d4,d1                          ; Pair 22 sample 2: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 22 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vbp02_22_fast_bp1u0p8         ; Pair 22 sample 2: skip the extra row step when the V fraction did not wrap.
    add.w   d4,d1                          ; Pair 22 sample 2: add the fractional carry texture row step.
.vbp02_22_fast_bp1u0p8:                  ; Pair 22 sample 2: V update complete for plus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 22: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 22: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 22: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 22: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 22: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 22: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 22: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 22: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 23 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 23 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 23 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 23 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 23 sample 1: advance integer U without fractional carry.
    add.w   d4,d1                          ; Pair 23 sample 1: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 23 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vbp01_23_fast_bp1u0p8         ; Pair 23 sample 1: skip the extra row step when the V fraction did not wrap.
    add.w   d4,d1                          ; Pair 23 sample 1: add the fractional carry texture row step.
.vbp01_23_fast_bp1u0p8:                  ; Pair 23 sample 1: V update complete for plus-one family.
    move.w  d0,d7                          ; Pair 23 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 23 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 23 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 23 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 23 sample 2: advance integer U without fractional carry.
    add.w   d4,d1                          ; Pair 23 sample 2: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 23 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vbp02_23_fast_bp1u0p8         ; Pair 23 sample 2: skip the extra row step when the V fraction did not wrap.
    add.w   d4,d1                          ; Pair 23 sample 2: add the fractional carry texture row step.
.vbp02_23_fast_bp1u0p8:                  ; Pair 23 sample 2: V update complete for plus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 23: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 23: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 23: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 23: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 23: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 23: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 23: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 23: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 24 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 24 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 24 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 24 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 24 sample 1: advance integer U without fractional carry.
    add.w   d4,d1                          ; Pair 24 sample 1: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 24 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vbp01_24_fast_bp1u0p8         ; Pair 24 sample 1: skip the extra row step when the V fraction did not wrap.
    add.w   d4,d1                          ; Pair 24 sample 1: add the fractional carry texture row step.
.vbp01_24_fast_bp1u0p8:                  ; Pair 24 sample 1: V update complete for plus-one family.
    move.w  d0,d7                          ; Pair 24 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 24 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 24 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 24 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 24 sample 2: advance integer U without fractional carry.
    add.w   d4,d1                          ; Pair 24 sample 2: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 24 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vbp02_24_fast_bp1u0p8         ; Pair 24 sample 2: skip the extra row step when the V fraction did not wrap.
    add.w   d4,d1                          ; Pair 24 sample 2: add the fractional carry texture row step.
.vbp02_24_fast_bp1u0p8:                  ; Pair 24 sample 2: V update complete for plus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 24: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 24: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 24: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 24: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 24: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 24: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 24: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 24: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 25 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 25 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 25 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 25 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 25 sample 1: advance integer U without fractional carry.
    add.w   d4,d1                          ; Pair 25 sample 1: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 25 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vbp01_25_fast_bp1u0p8         ; Pair 25 sample 1: skip the extra row step when the V fraction did not wrap.
    add.w   d4,d1                          ; Pair 25 sample 1: add the fractional carry texture row step.
.vbp01_25_fast_bp1u0p8:                  ; Pair 25 sample 1: V update complete for plus-one family.
    move.w  d0,d7                          ; Pair 25 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 25 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 25 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 25 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 25 sample 2: advance integer U without fractional carry.
    add.w   d4,d1                          ; Pair 25 sample 2: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 25 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vbp02_25_fast_bp1u0p8         ; Pair 25 sample 2: skip the extra row step when the V fraction did not wrap.
    add.w   d4,d1                          ; Pair 25 sample 2: add the fractional carry texture row step.
.vbp02_25_fast_bp1u0p8:                  ; Pair 25 sample 2: V update complete for plus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 25: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 25: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 25: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 25: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 25: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 25: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 25: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 25: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 26 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 26 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 26 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 26 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 26 sample 1: advance integer U without fractional carry.
    add.w   d4,d1                          ; Pair 26 sample 1: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 26 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vbp01_26_fast_bp1u0p8         ; Pair 26 sample 1: skip the extra row step when the V fraction did not wrap.
    add.w   d4,d1                          ; Pair 26 sample 1: add the fractional carry texture row step.
.vbp01_26_fast_bp1u0p8:                  ; Pair 26 sample 1: V update complete for plus-one family.
    move.w  d0,d7                          ; Pair 26 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 26 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 26 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 26 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 26 sample 2: advance integer U without fractional carry.
    add.w   d4,d1                          ; Pair 26 sample 2: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 26 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vbp12_26_fast_bp1u0p8             ; Pair 26 sample 2: skip the extra row step when the V fraction did not wrap.
    add.w   d4,d1                      ; Pair 26 sample 2: add the fractional carry texture row step.
.vbp12_26_fast_bp1u0p8:                      ; Pair 26 sample 2: V update complete for plus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 26: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 26: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 26: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 26: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 26: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 26: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 26: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 26: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 27 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 27 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 27 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 27 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 27 sample 1: advance integer U without fractional carry.
    add.w   d4,d1                          ; Pair 27 sample 1: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 27 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vbp11_27_fast_bp1u0p8             ; Pair 27 sample 1: skip the extra row step when the V fraction did not wrap.
    add.w   d4,d1                      ; Pair 27 sample 1: add the fractional carry texture row step.
.vbp11_27_fast_bp1u0p8:                      ; Pair 27 sample 1: V update complete for plus-one family.
    move.w  d0,d7                          ; Pair 27 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 27 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 27 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 27 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 27 sample 2: advance integer U without fractional carry.
    add.w   d4,d1                          ; Pair 27 sample 2: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 27 sample 2: add fractional V step to the high byte of d2.
    bcc.s   .vbp12_27_fast_bp1u0p8             ; Pair 27 sample 2: skip the extra row step when the V fraction did not wrap.
    add.w   d4,d1                      ; Pair 27 sample 2: add the fractional carry texture row step.
.vbp12_27_fast_bp1u0p8:                      ; Pair 27 sample 2: V update complete for plus-one family.
    or.l    (a1,a2.w),d7                  ; Pair 27: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 27: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 27: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 27: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 27: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 27: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 27: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 27: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 28 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 28 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 28 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 28 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 28 sample 1: advance integer U without fractional carry.
    add.w   d4,d1                          ; Pair 28 sample 1: apply the mandatory plus-one texture row step.
    add.w   d5,d2                          ; Pair 28 sample 1: add fractional V step to the high byte of d2.
    bcc.s   .vbp11_28_fast_bp1u0p8             ; Pair 28 sample 1: skip the extra row step when the V fraction did not wrap.
    add.w   d4,d1                      ; Pair 28 sample 1: add the fractional carry texture row step.
.vbp11_28_fast_bp1u0p8:                      ; Pair 28 sample 1: V update complete for plus-one family.
    move.w  d0,d7                          ; Pair 28 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 28 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 28 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 28 sample 2: fetch the low-nibble contribution into d7.
    ;                                      ; Pair 28 sample 2: skip the final accumulator update; post-row delta includes it.
    or.l    (a1,a2.w),d7                  ; Pair 28: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 28: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 28: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 28: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 28: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 28: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 28: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 28: store plane 1 byte and advance plane 1.
    swap    d5                             ; Move the row count into the low word for DBRA.
    dbra    d5,.fast_bp1u0p8_loop          ; Render the next logical row until all rows are complete.
    lea     STACK_TEMP_BYTES(sp),sp        ; Discard the temporary row-prefix and post-row stack slots.
    movem.l (sp)+,d2-d7/a2-a6              ; Restore all preserved registers.
    rts                                    ; Return to the C main loop without an extra final branch.

_RenderFastBm2U0P8Entry::                ; Family entry for minus-two integer V row base and DuL equal to zero and integrated pair 08.
    move.w  #$0200,d4                      ; Reuse the unused U-fraction register as a one-texture-row quantum.
    bra.s   .fast_bm2u0p8_after_swap       ; Enter the first row without applying the post-row delta.
.fast_bm2u0p8_loop:                      ; Start of the next logical row after DBRA branched.
    swap    d5                             ; Restore row count to the high word and V step to the low word.
.fast_bm2u0p8_post_row:                  ; Advance the rolling U/V seed from the previous row end to this row prefix.
    add.b   STACK_POST_DUL_BYTE(sp),d2     ; Apply the post-row fractional U delta and set X for the integer carry.
    move.w  STACK_POST_DUC(sp),d7          ; Load the post-row integer U delta into scratch register d7.
    addx.w  d7,d0                          ; Apply the post-row integer U delta plus the fractional carry.
    add.w   STACK_POST_VBASE(sp),d1        ; Apply the signed V row-base delta in texture-byte units.
    add.w   STACK_POST_VREM(sp),d2         ; Apply the post-row V fractional delta and set carry on row crossing.
    bcc.s   .fast_bm2u0p8_post_no_vcarry   ; Skip the extra V row increment when the post-row fraction did not wrap.
    add.w   d4,d1                          ; Apply the extra V row increment produced by the post-row fractional carry.
.fast_bm2u0p8_post_no_vcarry:            ; Post-row V carry handling is complete.
.fast_bm2u0p8_after_swap:                ; Row setup with the rolling seed already prepared for this row.
    movea.l (sp),a2            ; Reload the current row-prefix pointer from the stack slot.

    move.l  (a2)+,(a5)+                    ; Copy prefix pairs 01-04 directly from row state to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix pairs 01-04 directly from row state to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix pairs 01-04 directly from row state to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix pairs 01-04 directly from row state to plane 3.

.fast_bm2u0p8_pair05_06_prefix:          ; Emit prefix pairs 05-06 as direct plane words.
    move.w  (a2)+,(a5)+                    ; Pairs 05-06: copy the two premerged plane 0 bytes and advance plane 0.
    move.w  (a2)+,(a4)+                    ; Pairs 05-06: copy the two premerged plane 1 bytes and advance plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 05-06: copy the two premerged plane 2 bytes and advance plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 05-06: copy the two premerged plane 3 bytes and advance plane 3.

.fast_bm2u0p8_pair07_08_prefix:            ; Emit integrated prefix pairs 07-08 as direct plane words.
    move.w  (a2)+,(a5)+                    ; Pairs 07-08: copy the two premerged plane 0 bytes and advance plane 0.
    move.w  (a2)+,(a4)+                    ; Pairs 07-08: copy the two premerged plane 1 bytes and advance plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 07-08: copy the two premerged plane 2 bytes and advance plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 07-08: copy the two premerged plane 3 bytes and advance plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 09-10: copy packed word to plane 0 (high byte = pair 09, low byte = pair 10).
    move.w  (a2)+,(a4)+                    ; Pairs 09-10: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 09-10: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 09-10: copy packed word to plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 11-12: copy packed word to plane 0 (high byte = pair 11, low byte = pair 12).
    move.w  (a2)+,(a4)+                    ; Pairs 11-12: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 11-12: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 11-12: copy packed word to plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 13-14: copy packed word to plane 0 (high byte = pair 13, low byte = pair 14).
    move.w  (a2)+,(a4)+                    ; Pairs 13-14: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 13-14: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 13-14: copy packed word to plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 15: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 15: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 15: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 15: copy precomputed plane 3 byte and advance plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 16: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 16: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 16: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 16: copy precomputed plane 3 byte and advance plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 17: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 17: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 17: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 17: copy precomputed plane 3 byte and advance plane 3.
    move.l  a2,(sp)            ; Store the next row-prefix pointer after the integrated pair 17 bytes.

    move.w  d0,d7                          ; Pair 18 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 18 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 18 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 18 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 18 sample 1: advance integer U without fractional carry.
    sub.w   d4,d1                          ; Pair 18 sample 1: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 18 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm21_18_fast_bm2u0p8         ; Pair 18 sample 1: skip the extra decrement when the fractional add carried.
    sub.w   d4,d1                          ; Pair 18 sample 1: apply the second row decrement without carry.
.vbm21_18_fast_bm2u0p8:                  ; Pair 18 sample 1: V update complete for minus-two family.
    move.w  d0,d7                          ; Pair 18 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 18 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 18 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 18 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 18 sample 2: advance integer U without fractional carry.
    sub.w   d4,d1                          ; Pair 18 sample 2: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 18 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm22_18_fast_bm2u0p8         ; Pair 18 sample 2: skip the extra decrement when the fractional add carried.
    sub.w   d4,d1                          ; Pair 18 sample 2: apply the second row decrement without carry.
.vbm22_18_fast_bm2u0p8:                  ; Pair 18 sample 2: V update complete for minus-two family.
    or.l    (a1,a2.w),d7                  ; Pair 18: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 18: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 18: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 18: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 18: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 18: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 18: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 18: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 19 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 19 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 19 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 19 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 19 sample 1: advance integer U without fractional carry.
    sub.w   d4,d1                          ; Pair 19 sample 1: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 19 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm21_19_fast_bm2u0p8         ; Pair 19 sample 1: skip the extra decrement when the fractional add carried.
    sub.w   d4,d1                          ; Pair 19 sample 1: apply the second row decrement without carry.
.vbm21_19_fast_bm2u0p8:                  ; Pair 19 sample 1: V update complete for minus-two family.
    move.w  d0,d7                          ; Pair 19 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 19 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 19 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 19 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 19 sample 2: advance integer U without fractional carry.
    sub.w   d4,d1                          ; Pair 19 sample 2: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 19 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm22_19_fast_bm2u0p8         ; Pair 19 sample 2: skip the extra decrement when the fractional add carried.
    sub.w   d4,d1                          ; Pair 19 sample 2: apply the second row decrement without carry.
.vbm22_19_fast_bm2u0p8:                  ; Pair 19 sample 2: V update complete for minus-two family.
    or.l    (a1,a2.w),d7                  ; Pair 19: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 19: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 19: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 19: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 19: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 19: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 19: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 19: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 20 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 20 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 20 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 20 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 20 sample 1: advance integer U without fractional carry.
    sub.w   d4,d1                          ; Pair 20 sample 1: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 20 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm21_20_fast_bm2u0p8         ; Pair 20 sample 1: skip the extra decrement when the fractional add carried.
    sub.w   d4,d1                          ; Pair 20 sample 1: apply the second row decrement without carry.
.vbm21_20_fast_bm2u0p8:                  ; Pair 20 sample 1: V update complete for minus-two family.
    move.w  d0,d7                          ; Pair 20 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 20 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 20 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 20 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 20 sample 2: advance integer U without fractional carry.
    sub.w   d4,d1                          ; Pair 20 sample 2: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 20 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm22_20_fast_bm2u0p8         ; Pair 20 sample 2: skip the extra decrement when the fractional add carried.
    sub.w   d4,d1                          ; Pair 20 sample 2: apply the second row decrement without carry.
.vbm22_20_fast_bm2u0p8:                  ; Pair 20 sample 2: V update complete for minus-two family.
    or.l    (a1,a2.w),d7                  ; Pair 20: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 20: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 20: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 20: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 20: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 20: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 20: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 20: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 21 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 21 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 21 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 21 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 21 sample 1: advance integer U without fractional carry.
    sub.w   d4,d1                          ; Pair 21 sample 1: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 21 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm21_21_fast_bm2u0p8         ; Pair 21 sample 1: skip the extra decrement when the fractional add carried.
    sub.w   d4,d1                          ; Pair 21 sample 1: apply the second row decrement without carry.
.vbm21_21_fast_bm2u0p8:                  ; Pair 21 sample 1: V update complete for minus-two family.
    move.w  d0,d7                          ; Pair 21 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 21 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 21 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 21 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 21 sample 2: advance integer U without fractional carry.
    sub.w   d4,d1                          ; Pair 21 sample 2: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 21 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm22_21_fast_bm2u0p8         ; Pair 21 sample 2: skip the extra decrement when the fractional add carried.
    sub.w   d4,d1                          ; Pair 21 sample 2: apply the second row decrement without carry.
.vbm22_21_fast_bm2u0p8:                  ; Pair 21 sample 2: V update complete for minus-two family.
    or.l    (a1,a2.w),d7                  ; Pair 21: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 21: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 21: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 21: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 21: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 21: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 21: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 21: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 22 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 22 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 22 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 22 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 22 sample 1: advance integer U without fractional carry.
    sub.w   d4,d1                          ; Pair 22 sample 1: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 22 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm21_22_fast_bm2u0p8         ; Pair 22 sample 1: skip the extra decrement when the fractional add carried.
    sub.w   d4,d1                          ; Pair 22 sample 1: apply the second row decrement without carry.
.vbm21_22_fast_bm2u0p8:                  ; Pair 22 sample 1: V update complete for minus-two family.
    move.w  d0,d7                          ; Pair 22 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 22 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 22 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 22 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 22 sample 2: advance integer U without fractional carry.
    sub.w   d4,d1                          ; Pair 22 sample 2: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 22 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm22_22_fast_bm2u0p8         ; Pair 22 sample 2: skip the extra decrement when the fractional add carried.
    sub.w   d4,d1                          ; Pair 22 sample 2: apply the second row decrement without carry.
.vbm22_22_fast_bm2u0p8:                  ; Pair 22 sample 2: V update complete for minus-two family.
    or.l    (a1,a2.w),d7                  ; Pair 22: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 22: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 22: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 22: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 22: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 22: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 22: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 22: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 23 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 23 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 23 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 23 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 23 sample 1: advance integer U without fractional carry.
    sub.w   d4,d1                          ; Pair 23 sample 1: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 23 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm21_23_fast_bm2u0p8         ; Pair 23 sample 1: skip the extra decrement when the fractional add carried.
    sub.w   d4,d1                          ; Pair 23 sample 1: apply the second row decrement without carry.
.vbm21_23_fast_bm2u0p8:                  ; Pair 23 sample 1: V update complete for minus-two family.
    move.w  d0,d7                          ; Pair 23 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 23 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 23 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 23 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 23 sample 2: advance integer U without fractional carry.
    sub.w   d4,d1                          ; Pair 23 sample 2: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 23 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm22_23_fast_bm2u0p8         ; Pair 23 sample 2: skip the extra decrement when the fractional add carried.
    sub.w   d4,d1                          ; Pair 23 sample 2: apply the second row decrement without carry.
.vbm22_23_fast_bm2u0p8:                  ; Pair 23 sample 2: V update complete for minus-two family.
    or.l    (a1,a2.w),d7                  ; Pair 23: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 23: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 23: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 23: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 23: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 23: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 23: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 23: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 24 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 24 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 24 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 24 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 24 sample 1: advance integer U without fractional carry.
    sub.w   d4,d1                          ; Pair 24 sample 1: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 24 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm21_24_fast_bm2u0p8         ; Pair 24 sample 1: skip the extra decrement when the fractional add carried.
    sub.w   d4,d1                          ; Pair 24 sample 1: apply the second row decrement without carry.
.vbm21_24_fast_bm2u0p8:                  ; Pair 24 sample 1: V update complete for minus-two family.
    move.w  d0,d7                          ; Pair 24 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 24 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 24 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 24 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 24 sample 2: advance integer U without fractional carry.
    sub.w   d4,d1                          ; Pair 24 sample 2: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 24 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm22_24_fast_bm2u0p8         ; Pair 24 sample 2: skip the extra decrement when the fractional add carried.
    sub.w   d4,d1                          ; Pair 24 sample 2: apply the second row decrement without carry.
.vbm22_24_fast_bm2u0p8:                  ; Pair 24 sample 2: V update complete for minus-two family.
    or.l    (a1,a2.w),d7                  ; Pair 24: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 24: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 24: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 24: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 24: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 24: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 24: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 24: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 25 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 25 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 25 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 25 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 25 sample 1: advance integer U without fractional carry.
    sub.w   d4,d1                          ; Pair 25 sample 1: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 25 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm21_25_fast_bm2u0p8         ; Pair 25 sample 1: skip the extra decrement when the fractional add carried.
    sub.w   d4,d1                          ; Pair 25 sample 1: apply the second row decrement without carry.
.vbm21_25_fast_bm2u0p8:                  ; Pair 25 sample 1: V update complete for minus-two family.
    move.w  d0,d7                          ; Pair 25 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 25 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 25 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 25 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 25 sample 2: advance integer U without fractional carry.
    sub.w   d4,d1                          ; Pair 25 sample 2: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 25 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm22_25_fast_bm2u0p8         ; Pair 25 sample 2: skip the extra decrement when the fractional add carried.
    sub.w   d4,d1                          ; Pair 25 sample 2: apply the second row decrement without carry.
.vbm22_25_fast_bm2u0p8:                  ; Pair 25 sample 2: V update complete for minus-two family.
    or.l    (a1,a2.w),d7                  ; Pair 25: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 25: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 25: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 25: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 25: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 25: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 25: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 25: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 26 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 26 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 26 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 26 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 26 sample 1: advance integer U without fractional carry.
    sub.w   d4,d1                          ; Pair 26 sample 1: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 26 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm21_26_fast_bm2u0p8         ; Pair 26 sample 1: skip the extra decrement when the fractional add carried.
    sub.w   d4,d1                          ; Pair 26 sample 1: apply the second row decrement without carry.
.vbm21_26_fast_bm2u0p8:                  ; Pair 26 sample 1: V update complete for minus-two family.
    move.w  d0,d7                          ; Pair 26 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 26 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 26 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 26 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 26 sample 2: advance integer U without fractional carry.
    sub.w   d4,d1                          ; Pair 26 sample 2: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 26 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm22_26_fast_bm2u0p8             ; Pair 26 sample 2: skip the extra decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 26 sample 2: decrement two wrapped texture rows without carry.
.vbm22_26_fast_bm2u0p8:                      ; Pair 26 sample 2: V update complete for minus-two family.
    or.l    (a1,a2.w),d7                  ; Pair 26: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 26: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 26: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 26: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 26: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 26: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 26: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 26: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 27 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 27 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 27 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 27 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 27 sample 1: advance integer U without fractional carry.
    sub.w   d4,d1                          ; Pair 27 sample 1: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 27 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm21_27_fast_bm2u0p8             ; Pair 27 sample 1: skip the extra decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 27 sample 1: decrement two wrapped texture rows without carry.
.vbm21_27_fast_bm2u0p8:                      ; Pair 27 sample 1: V update complete for minus-two family.
    move.w  d0,d7                          ; Pair 27 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 27 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 27 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 27 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 27 sample 2: advance integer U without fractional carry.
    sub.w   d4,d1                          ; Pair 27 sample 2: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 27 sample 2: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm22_27_fast_bm2u0p8             ; Pair 27 sample 2: skip the extra decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 27 sample 2: decrement two wrapped texture rows without carry.
.vbm22_27_fast_bm2u0p8:                      ; Pair 27 sample 2: V update complete for minus-two family.
    or.l    (a1,a2.w),d7                  ; Pair 27: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 27: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 27: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 27: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 27: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 27: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 27: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 27: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 28 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 28 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 28 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 28 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 28 sample 1: advance integer U without fractional carry.
    sub.w   d4,d1                          ; Pair 28 sample 1: apply the mandatory minus-one texture row step.
    add.w   d5,d2                          ; Pair 28 sample 1: add negative fractional V step to the high byte of d2.
    bcs.s   .vbm21_28_fast_bm2u0p8             ; Pair 28 sample 1: skip the extra decrement when the fractional add carried.
    subi.w  #$0200,d1                      ; Pair 28 sample 1: decrement two wrapped texture rows without carry.
.vbm21_28_fast_bm2u0p8:                      ; Pair 28 sample 1: V update complete for minus-two family.
    move.w  d0,d7                          ; Pair 28 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 28 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 28 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 28 sample 2: fetch the low-nibble contribution into d7.
    ;                                      ; Pair 28 sample 2: skip the final accumulator update; post-row delta includes it.
    or.l    (a1,a2.w),d7                  ; Pair 28: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 28: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 28: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 28: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 28: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 28: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 28: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 28: store plane 1 byte and advance plane 1.
    swap    d5                             ; Move the row count into the low word for DBRA.
    dbra    d5,.fast_bm2u0p8_loop          ; Render the next logical row until all rows are complete.
    lea     STACK_TEMP_BYTES(sp),sp        ; Discard the temporary row-prefix and post-row stack slots.
    movem.l (sp)+,d2-d7/a2-a6              ; Restore all preserved registers.
    rts                                    ; Return to the C main loop without an extra final branch.

_RenderFastB0V0Entry::                   ; Family entry for zero integer V row base and DvRem equal to zero.
    bra.s   .fast_b0v0_after_swap          ; Enter the first row without applying the post-row delta.
.fast_b0v0_loop:                         ; Start of the next logical row after DBRA branched.
    swap    d5                             ; Restore row count to the high word and V step to the low word.
.fast_b0v0_post_row:                     ; Advance the rolling U/V seed from the previous row end to this row prefix.
    add.b   STACK_POST_DUL_BYTE(sp),d2     ; Apply the post-row fractional U delta and set X for the integer carry.
    move.w  STACK_POST_DUC(sp),d7          ; Load the post-row integer U delta into scratch register d7.
    addx.w  d7,d0                          ; Apply the post-row integer U delta plus the fractional carry.
    add.w   STACK_POST_VBASE(sp),d1        ; Apply the signed V row-base delta in texture-byte units.
    add.w   STACK_POST_VREM(sp),d2         ; Apply the post-row V fractional delta and set carry on row crossing.
    bcc.s   .fast_b0v0_post_no_vcarry      ; Skip the extra V row increment when the post-row fraction did not wrap.
    addi.w  #$0200,d1                      ; Apply the extra V row increment produced by the post-row fractional carry.
.fast_b0v0_post_no_vcarry:               ; Post-row V carry handling is complete.
.fast_b0v0_after_swap:                   ; Row setup with the rolling seed already prepared for this row.
    movea.l (sp),a2            ; Reload the current row-prefix pointer from the stack slot.

    move.l  (a2)+,(a5)+                    ; Copy prefix pairs 01-04 directly from row state to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix pairs 01-04 directly from row state to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix pairs 01-04 directly from row state to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix pairs 01-04 directly from row state to plane 3.

.fast_b0v0_pair05_06_prefix:             ; Emit prefix pairs 05-06 as direct plane words.
    move.w  (a2)+,(a5)+                    ; Pairs 05-06: copy the two premerged plane 0 bytes and advance plane 0.
    move.w  (a2)+,(a4)+                    ; Pairs 05-06: copy the two premerged plane 1 bytes and advance plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 05-06: copy the two premerged plane 2 bytes and advance plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 05-06: copy the two premerged plane 3 bytes and advance plane 3.

.fast_b0v0_pair07_08_prefix:              ; Emit prefix pairs 07-08 as direct plane words.
    move.w  (a2)+,(a5)+                    ; Pairs 07-08: copy the two premerged plane 0 bytes and advance plane 0.
    move.w  (a2)+,(a4)+                    ; Pairs 07-08: copy the two premerged plane 1 bytes and advance plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 07-08: copy the two premerged plane 2 bytes and advance plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 07-08: copy the two premerged plane 3 bytes and advance plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 09-10: copy packed word to plane 0 (high byte = pair 09, low byte = pair 10).
    move.w  (a2)+,(a4)+                    ; Pairs 09-10: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 09-10: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 09-10: copy packed word to plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 11-12: copy packed word to plane 0 (high byte = pair 11, low byte = pair 12).
    move.w  (a2)+,(a4)+                    ; Pairs 11-12: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 11-12: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 11-12: copy packed word to plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 13-14: copy packed word to plane 0 (high byte = pair 13, low byte = pair 14).
    move.w  (a2)+,(a4)+                    ; Pairs 13-14: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 13-14: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 13-14: copy packed word to plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 15: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 15: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 15: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 15: copy precomputed plane 3 byte and advance plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 16: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 16: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 16: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 16: copy precomputed plane 3 byte and advance plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 17: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 17: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 17: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 17: copy precomputed plane 3 byte and advance plane 3.
    move.l  a2,(sp)            ; Store the next row-prefix pointer after the integrated pair 17 bytes.

    move.w  d0,d7                          ; Pair 18 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 18 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 18 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 18 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 18 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 18 sample 1: advance integer U with the fractional carry.
    ;                                      ; Pair 18 sample 1: V is constant for this frame, so no V update is emitted.
    move.w  d0,d7                          ; Pair 18 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 18 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 18 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 18 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 18 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 18 sample 2: advance integer U with the fractional carry.
    ;                                      ; Pair 18 sample 2: V is constant for this frame, so no V update is emitted.
    or.l    (a1,a2.w),d7                  ; Pair 18: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 18: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 18: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 18: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 18: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 18: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 18: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 18: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 19 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 19 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 19 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 19 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 19 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 19 sample 1: advance integer U with the fractional carry.
    ;                                      ; Pair 19 sample 1: V is constant for this frame, so no V update is emitted.
    move.w  d0,d7                          ; Pair 19 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 19 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 19 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 19 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 19 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 19 sample 2: advance integer U with the fractional carry.
    ;                                      ; Pair 19 sample 2: V is constant for this frame, so no V update is emitted.
    or.l    (a1,a2.w),d7                  ; Pair 19: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 19: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 19: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 19: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 19: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 19: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 19: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 19: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 20 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 20 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 20 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 20 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 20 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 20 sample 1: advance integer U with the fractional carry.
    ;                                      ; Pair 20 sample 1: V is constant for this frame, so no V update is emitted.
    move.w  d0,d7                          ; Pair 20 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 20 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 20 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 20 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 20 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 20 sample 2: advance integer U with the fractional carry.
    ;                                      ; Pair 20 sample 2: V is constant for this frame, so no V update is emitted.
    or.l    (a1,a2.w),d7                  ; Pair 20: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 20: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 20: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 20: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 20: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 20: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 20: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 20: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 21 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 21 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 21 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 21 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 21 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 21 sample 1: advance integer U with the fractional carry.
    ;                                      ; Pair 21 sample 1: V is constant for this frame, so no V update is emitted.
    move.w  d0,d7                          ; Pair 21 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 21 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 21 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 21 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 21 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 21 sample 2: advance integer U with the fractional carry.
    ;                                      ; Pair 21 sample 2: V is constant for this frame, so no V update is emitted.
    or.l    (a1,a2.w),d7                  ; Pair 21: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 21: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 21: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 21: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 21: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 21: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 21: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 21: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 22 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 22 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 22 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 22 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 22 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 22 sample 1: advance integer U with the fractional carry.
    ;                                      ; Pair 22 sample 1: V is constant for this frame, so no V update is emitted.
    move.w  d0,d7                          ; Pair 22 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 22 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 22 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 22 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 22 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 22 sample 2: advance integer U with the fractional carry.
    ;                                      ; Pair 22 sample 2: V is constant for this frame, so no V update is emitted.
    or.l    (a1,a2.w),d7                  ; Pair 22: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 22: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 22: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 22: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 22: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 22: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 22: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 22: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 23 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 23 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 23 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 23 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 23 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 23 sample 1: advance integer U with the fractional carry.
    ;                                      ; Pair 23 sample 1: V is constant for this frame, so no V update is emitted.
    move.w  d0,d7                          ; Pair 23 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 23 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 23 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 23 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 23 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 23 sample 2: advance integer U with the fractional carry.
    ;                                      ; Pair 23 sample 2: V is constant for this frame, so no V update is emitted.
    or.l    (a1,a2.w),d7                  ; Pair 23: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 23: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 23: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 23: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 23: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 23: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 23: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 23: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 24 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 24 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 24 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 24 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 24 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 24 sample 1: advance integer U with the fractional carry.
    ;                                      ; Pair 24 sample 1: V is constant for this frame, so no V update is emitted.
    move.w  d0,d7                          ; Pair 24 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 24 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 24 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 24 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 24 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 24 sample 2: advance integer U with the fractional carry.
    ;                                      ; Pair 24 sample 2: V is constant for this frame, so no V update is emitted.
    or.l    (a1,a2.w),d7                  ; Pair 24: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 24: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 24: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 24: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 24: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 24: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 24: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 24: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 25 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 25 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 25 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 25 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 25 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 25 sample 1: advance integer U with the fractional carry.
    ;                                      ; Pair 25 sample 1: V is constant for this frame, so no V update is emitted.
    move.w  d0,d7                          ; Pair 25 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 25 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 25 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 25 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 25 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 25 sample 2: advance integer U with the fractional carry.
    ;                                      ; Pair 25 sample 2: V is constant for this frame, so no V update is emitted.
    or.l    (a1,a2.w),d7                  ; Pair 25: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 25: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 25: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 25: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 25: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 25: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 25: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 25: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 26 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 26 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 26 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 26 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 26 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 26 sample 1: advance integer U with the fractional carry.
    ;                                      ; Pair 26 sample 1: V is constant for this frame, so no V update is emitted.
    move.w  d0,d7                          ; Pair 26 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 26 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 26 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 26 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 26 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 26 sample 2: advance integer U with the fractional carry.
    ;                                      ; Pair 26 sample 2: V is constant for this frame, so no V update is emitted.
    or.l    (a1,a2.w),d7                  ; Pair 26: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 26: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 26: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 26: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 26: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 26: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 26: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 26: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 27 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 27 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 27 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 27 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 27 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 27 sample 1: advance integer U with the fractional carry.
    ;                                      ; Pair 27 sample 1: V is constant for this frame, so no V update is emitted.
    move.w  d0,d7                          ; Pair 27 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 27 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 27 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 27 sample 2: fetch the low-nibble contribution into d7.
    add.b   d4,d2                          ; Pair 27 sample 2: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 27 sample 2: advance integer U with the fractional carry.
    ;                                      ; Pair 27 sample 2: V is constant for this frame, so no V update is emitted.
    or.l    (a1,a2.w),d7                  ; Pair 27: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 27: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 27: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 27: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 27: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 27: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 27: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 27: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 28 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 28 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 28 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 28 sample 1: preserve the signed table offset in a2.
    add.b   d4,d2                          ; Pair 28 sample 1: advance the fractional U accumulator.
    addx.w  d3,d0                          ; Pair 28 sample 1: advance integer U with the fractional carry.
    ;                                      ; Pair 28 sample 1: V is constant for this frame, so no V update is emitted.
    move.w  d0,d7                          ; Pair 28 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 28 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 28 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 28 sample 2: fetch the low-nibble contribution into d7.
    ;                                      ; Pair 28 sample 2: skip the final accumulator update; post-row delta includes it.
    or.l    (a1,a2.w),d7                  ; Pair 28: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 28: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 28: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 28: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 28: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 28: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 28: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 28: store plane 1 byte and advance plane 1.
    swap    d5                             ; Move the row count into the low word for DBRA.
    dbra    d5,.fast_b0v0_loop             ; Render the next logical row until all rows are complete.
    lea     STACK_TEMP_BYTES(sp),sp        ; Discard the temporary row-prefix and post-row stack slots.
    movem.l (sp)+,d2-d7/a2-a6              ; Restore all preserved registers.
    rts                                    ; Return to the C main loop without an extra final branch.

_RenderFastB0U0V0Entry::                 ; Family entry for zero integer V row base and DuL equal to zero and DvRem equal to zero.
    move.w  #$0200,d4                      ; Reuse the unused U-fraction register as a one-texture-row quantum.
    bra.s   .fast_b0u0v0_after_swap        ; Enter the first row without applying the post-row delta.
.fast_b0u0v0_loop:                       ; Start of the next logical row after DBRA branched.
    swap    d5                             ; Restore row count to the high word and V step to the low word.
.fast_b0u0v0_post_row:                   ; Advance the rolling U/V seed from the previous row end to this row prefix.
    add.b   STACK_POST_DUL_BYTE(sp),d2     ; Apply the post-row fractional U delta and set X for the integer carry.
    move.w  STACK_POST_DUC(sp),d7          ; Load the post-row integer U delta into scratch register d7.
    addx.w  d7,d0                          ; Apply the post-row integer U delta plus the fractional carry.
    add.w   STACK_POST_VBASE(sp),d1        ; Apply the signed V row-base delta in texture-byte units.
    add.w   STACK_POST_VREM(sp),d2         ; Apply the post-row V fractional delta and set carry on row crossing.
    bcc.s   .fast_b0u0v0_post_no_vcarry    ; Skip the extra V row increment when the post-row fraction did not wrap.
    add.w   d4,d1                          ; Apply the extra V row increment produced by the post-row fractional carry.
.fast_b0u0v0_post_no_vcarry:             ; Post-row V carry handling is complete.
.fast_b0u0v0_after_swap:                 ; Row setup with the rolling seed already prepared for this row.
    movea.l (sp),a2            ; Reload the current row-prefix pointer from the stack slot.

    move.l  (a2)+,(a5)+                    ; Copy prefix pairs 01-04 directly from row state to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix pairs 01-04 directly from row state to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix pairs 01-04 directly from row state to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix pairs 01-04 directly from row state to plane 3.

.fast_b0u0v0_pair05_06_prefix:           ; Emit prefix pairs 05-06 as direct plane words.
    move.w  (a2)+,(a5)+                    ; Pairs 05-06: copy the two premerged plane 0 bytes and advance plane 0.
    move.w  (a2)+,(a4)+                    ; Pairs 05-06: copy the two premerged plane 1 bytes and advance plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 05-06: copy the two premerged plane 2 bytes and advance plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 05-06: copy the two premerged plane 3 bytes and advance plane 3.

.fast_b0u0v0_pair07_08_prefix:              ; Emit prefix pairs 07-08 as direct plane words.
    move.w  (a2)+,(a5)+                    ; Pairs 07-08: copy the two premerged plane 0 bytes and advance plane 0.
    move.w  (a2)+,(a4)+                    ; Pairs 07-08: copy the two premerged plane 1 bytes and advance plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 07-08: copy the two premerged plane 2 bytes and advance plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 07-08: copy the two premerged plane 3 bytes and advance plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 09-10: copy packed word to plane 0 (high byte = pair 09, low byte = pair 10).
    move.w  (a2)+,(a4)+                    ; Pairs 09-10: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 09-10: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 09-10: copy packed word to plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 11-12: copy packed word to plane 0 (high byte = pair 11, low byte = pair 12).
    move.w  (a2)+,(a4)+                    ; Pairs 11-12: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 11-12: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 11-12: copy packed word to plane 3.
    move.w  (a2)+,(a5)+                    ; Pairs 13-14: copy packed word to plane 0 (high byte = pair 13, low byte = pair 14).
    move.w  (a2)+,(a4)+                    ; Pairs 13-14: copy packed word to plane 1.
    move.w  (a2)+,(a6)+                    ; Pairs 13-14: copy packed word to plane 2.
    move.w  (a2)+,(a0)+                    ; Pairs 13-14: copy packed word to plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 15: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 15: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 15: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 15: copy precomputed plane 3 byte and advance plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 16: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 16: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 16: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 16: copy precomputed plane 3 byte and advance plane 3.
    move.b  (a2)+,(a5)+                    ; Pair 17: copy precomputed plane 0 byte and advance plane 0.
    move.b  (a2)+,(a4)+                    ; Pair 17: copy precomputed plane 1 byte and advance plane 1.
    move.b  (a2)+,(a6)+                    ; Pair 17: copy precomputed plane 2 byte and advance plane 2.
    move.b  (a2)+,(a0)+                    ; Pair 17: copy precomputed plane 3 byte and advance plane 3.
    move.l  a2,(sp)            ; Store the next row-prefix pointer after the integrated pair 17 bytes.

    move.w  d0,d7                          ; Pair 18 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 18 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 18 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 18 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 18 sample 1: advance integer U without fractional carry.
    ;                                      ; Pair 18 sample 1: V is constant for this frame, so no V update is emitted.
    move.w  d0,d7                          ; Pair 18 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 18 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 18 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 18 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 18 sample 2: advance integer U without fractional carry.
    ;                                      ; Pair 18 sample 2: V is constant for this frame, so no V update is emitted.
    or.l    (a1,a2.w),d7                  ; Pair 18: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 18: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 18: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 18: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 18: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 18: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 18: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 18: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 19 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 19 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 19 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 19 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 19 sample 1: advance integer U without fractional carry.
    ;                                      ; Pair 19 sample 1: V is constant for this frame, so no V update is emitted.
    move.w  d0,d7                          ; Pair 19 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 19 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 19 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 19 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 19 sample 2: advance integer U without fractional carry.
    ;                                      ; Pair 19 sample 2: V is constant for this frame, so no V update is emitted.
    or.l    (a1,a2.w),d7                  ; Pair 19: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 19: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 19: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 19: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 19: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 19: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 19: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 19: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 20 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 20 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 20 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 20 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 20 sample 1: advance integer U without fractional carry.
    ;                                      ; Pair 20 sample 1: V is constant for this frame, so no V update is emitted.
    move.w  d0,d7                          ; Pair 20 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 20 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 20 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 20 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 20 sample 2: advance integer U without fractional carry.
    ;                                      ; Pair 20 sample 2: V is constant for this frame, so no V update is emitted.
    or.l    (a1,a2.w),d7                  ; Pair 20: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 20: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 20: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 20: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 20: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 20: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 20: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 20: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 21 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 21 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 21 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 21 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 21 sample 1: advance integer U without fractional carry.
    ;                                      ; Pair 21 sample 1: V is constant for this frame, so no V update is emitted.
    move.w  d0,d7                          ; Pair 21 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 21 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 21 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 21 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 21 sample 2: advance integer U without fractional carry.
    ;                                      ; Pair 21 sample 2: V is constant for this frame, so no V update is emitted.
    or.l    (a1,a2.w),d7                  ; Pair 21: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 21: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 21: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 21: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 21: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 21: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 21: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 21: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 22 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 22 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 22 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 22 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 22 sample 1: advance integer U without fractional carry.
    ;                                      ; Pair 22 sample 1: V is constant for this frame, so no V update is emitted.
    move.w  d0,d7                          ; Pair 22 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 22 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 22 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 22 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 22 sample 2: advance integer U without fractional carry.
    ;                                      ; Pair 22 sample 2: V is constant for this frame, so no V update is emitted.
    or.l    (a1,a2.w),d7                  ; Pair 22: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 22: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 22: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 22: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 22: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 22: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 22: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 22: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 23 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 23 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 23 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 23 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 23 sample 1: advance integer U without fractional carry.
    ;                                      ; Pair 23 sample 1: V is constant for this frame, so no V update is emitted.
    move.w  d0,d7                          ; Pair 23 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 23 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 23 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 23 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 23 sample 2: advance integer U without fractional carry.
    ;                                      ; Pair 23 sample 2: V is constant for this frame, so no V update is emitted.
    or.l    (a1,a2.w),d7                  ; Pair 23: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 23: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 23: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 23: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 23: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 23: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 23: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 23: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 24 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 24 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 24 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 24 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 24 sample 1: advance integer U without fractional carry.
    ;                                      ; Pair 24 sample 1: V is constant for this frame, so no V update is emitted.
    move.w  d0,d7                          ; Pair 24 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 24 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 24 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 24 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 24 sample 2: advance integer U without fractional carry.
    ;                                      ; Pair 24 sample 2: V is constant for this frame, so no V update is emitted.
    or.l    (a1,a2.w),d7                  ; Pair 24: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 24: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 24: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 24: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 24: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 24: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 24: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 24: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 25 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 25 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 25 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 25 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 25 sample 1: advance integer U without fractional carry.
    ;                                      ; Pair 25 sample 1: V is constant for this frame, so no V update is emitted.
    move.w  d0,d7                          ; Pair 25 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 25 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 25 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 25 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 25 sample 2: advance integer U without fractional carry.
    ;                                      ; Pair 25 sample 2: V is constant for this frame, so no V update is emitted.
    or.l    (a1,a2.w),d7                  ; Pair 25: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 25: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 25: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 25: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 25: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 25: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 25: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 25: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 26 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 26 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 26 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 26 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 26 sample 1: advance integer U without fractional carry.
    ;                                      ; Pair 26 sample 1: V is constant for this frame, so no V update is emitted.
    move.w  d0,d7                          ; Pair 26 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 26 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 26 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 26 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 26 sample 2: advance integer U without fractional carry.
    ;                                      ; Pair 26 sample 2: V is constant for this frame, so no V update is emitted.
    or.l    (a1,a2.w),d7                  ; Pair 26: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 26: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 26: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 26: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 26: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 26: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 26: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 26: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 27 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 27 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 27 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 27 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 27 sample 1: advance integer U without fractional carry.
    ;                                      ; Pair 27 sample 1: V is constant for this frame, so no V update is emitted.
    move.w  d0,d7                          ; Pair 27 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 27 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 27 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 27 sample 2: fetch the low-nibble contribution into d7.
    add.w   d3,d0                          ; Pair 27 sample 2: advance integer U without fractional carry.
    ;                                      ; Pair 27 sample 2: V is constant for this frame, so no V update is emitted.
    or.l    (a1,a2.w),d7                  ; Pair 27: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 27: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 27: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 27: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 27: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 27: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 27: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 27: store plane 1 byte and advance plane 1.
    move.w  d0,d7                          ; Pair 28 sample 1: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 28 sample 1: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 28 sample 1: add the wrapped V row offset.
    movea.w d7,a2                          ; Pair 28 sample 1: preserve the signed table offset in a2.
    add.w   d3,d0                          ; Pair 28 sample 1: advance integer U without fractional carry.
    ;                                      ; Pair 28 sample 1: V is constant for this frame, so no V update is emitted.
    move.w  d0,d7                          ; Pair 28 sample 2: copy current U coordinate into d7.
    and.w   d6,d7                          ; Pair 28 sample 2: wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Pair 28 sample 2: add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Pair 28 sample 2: fetch the low-nibble contribution into d7.
    ;                                      ; Pair 28 sample 2: skip the final accumulator update; post-row delta includes it.
    or.l    (a1,a2.w),d7                  ; Pair 28: merge the high-nibble contribution from sample 1.
    move.b  d7,(a5)+                       ; Pair 28: store plane 0 byte and advance plane 0.
    swap    d7                             ; Pair 28: expose the plane 2 byte in the low byte.
    move.b  d7,(a6)+                       ; Pair 28: store plane 2 byte and advance plane 2.
    lsr.l   #8,d7                          ; Pair 28: expose the plane 3 byte while preserving plane 1 for the final swap.
    move.b  d7,(a0)+                       ; Pair 28: store plane 3 byte and advance plane 3.
    swap    d7                             ; Pair 28: expose the plane 1 byte in the low byte.
    move.b  d7,(a4)+                       ; Pair 28: store plane 1 byte and advance plane 1.
    swap    d5                             ; Move the row count into the low word for DBRA.
    dbra    d5,.fast_b0u0v0_loop           ; Render the next logical row until all rows are complete.
    lea     STACK_TEMP_BYTES(sp),sp        ; Discard the temporary row-prefix and post-row stack slots.
    movem.l (sp)+,d2-d7/a2-a6              ; Restore all preserved registers.
    rts                                    ; Return to the C main loop without an extra final branch.

