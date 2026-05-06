    machine 68000                          ; Select the plain 68000 instruction set.

    include "lwmf/lwmf_hardware_regs.i"    ; Keep the project hardware include available.

ROTO_ROWS              equ 48              ; Rendered logical rows.
ROTO_PAIR_COUNT        equ 28              ; Logical texel pairs per row.
ROTO_PREFIX_PAIRS      equ 17              ; Pairs covered by the precomputed row prefix.
ROTO_RUNTIME_PAIRS     equ (ROTO_PAIR_COUNT-ROTO_PREFIX_PAIRS) ; Pairs rendered after the precomputed prefix.
ROTO_PLANE_STRIDE      equ 28              ; Bytes per rendered row in one bitplane.
ROTO_PLANE_BYTES       equ (ROTO_PLANE_STRIDE*ROTO_ROWS) ; Bytes in one contiguous rendered bitplane.
ROTO_FRAME_DUC         equ 0               ; Frame offset of the signed integer U step.
ROTO_FRAME_DUL         equ 2               ; Frame offset of the fractional U step byte.
ROTO_FRAME_DVREM       equ 3               ; Frame offset of the fractional V step byte.
ROTO_FRAME_ENTRY       equ 4               ; Frame offset of the selected family entry pointer.
ROTO_FRAME_SEED0       equ 8               ; Frame offset of the first-row packed V row bits and U coordinate.
ROTO_FRAME_REMS0       equ 10              ; Frame offset of the first-row packed V and U fractional remainders.
ROTO_FRAME_POST_DUC    equ 12              ; Frame offset of the post-row signed integer U delta.
ROTO_FRAME_POST_DUL    equ 14              ; Frame offset of the post-row fractional U delta byte.
ROTO_FRAME_POST_VBASE  equ 16              ; Frame offset of the post-row signed V row-base delta in texture bytes.
ROTO_FRAME_POST_VREM   equ 18              ; Frame offset of the post-row V fractional delta shifted into the high byte.
ROTO_FRAME_NEXT        equ 20              ; Frame offset of the next-frame pointer.
ROTO_FRAME_ROWS        equ 24              ; Frame offset of the first row prefix state.
ROTO_ROW_SIZE          equ 68              ; Size of one row prefix state.
STACK_ROWPTR           equ 0               ; Stack offset of the current row-prefix pointer.
STACK_POST_DUL         equ 4               ; Stack offset of the aligned post-row fractional U delta.
STACK_POST_DUL_BYTE    equ 5               ; Stack byte offset of the post-row fractional U delta.
STACK_POST_DUC         equ 6               ; Stack offset of the post-row integer U delta.
STACK_POST_VBASE       equ 8               ; Stack offset of the post-row V row-base delta.
STACK_POST_VREM        equ 10              ; Stack offset of the post-row V fractional delta.
STACK_ROWCOUNT         equ 12              ; Stack offset of the remaining row counter.
STACK_TEMP_BYTES       equ 14              ; Bytes of temporary renderer stack data.

; -----------------------------------------------------------------------------
; void RenderFrameAsm(__reg("a0") UBYTE *Dest, __reg("a1") const void *FrameState)
; -----------------------------------------------------------------------------

_RenderFrameAsm::                          ; Entry from C with destination in a0 and frame state in a1.
    movem.l d2-d7/a2-a6,-(sp)              ; Preserve all registers used by the renderer.
    lea     -STACK_TEMP_BYTES(sp),sp       ; Reserve compact per-frame renderer state.
    movea.l a0,a5                          ; Keep plane 0 destination pointer in a5.
    move.w  ROTO_FRAME_SEED0(a1),d0        ; Load the first-row U seed after the prefix.
    move.w  ROTO_FRAME_REMS0(a1),d2        ; Load the first-row V/U fractional remainders.
    move.w  d0,d1                          ; Copy the packed seed for V row extraction.
    andi.w  #$FE00,d1                      ; Keep only the wrapped V row offset.
    lea     ROTO_FRAME_ROWS(a1),a2         ; Point to the first row prefix state.
    move.l  a2,(sp)            ; Cache the current row prefix pointer.
    move.w  ROTO_FRAME_POST_VREM(a1),STACK_POST_VREM(sp) ; Cache the post-row V fraction delta.
    move.w  ROTO_FRAME_POST_VBASE(a1),STACK_POST_VBASE(sp) ; Cache the post-row V row delta.
    move.w  ROTO_FRAME_POST_DUC(a1),STACK_POST_DUC(sp) ; Cache the post-row integer U delta.
    clr.w   STACK_POST_DUL(sp)             ; Clear the aligned post-row U fraction cache.
    move.b  ROTO_FRAME_POST_DUL(a1),STACK_POST_DUL_BYTE(sp) ; Cache the post-row U fraction byte.
    move.w  #(ROTO_ROWS-1),STACK_ROWCOUNT(sp) ; Prepare the visible row count.
    move.w  (a1),d3          ; Load the signed integer U step.
    moveq   #0,d4                          ; Clear the fractional U step register.
    move.b  ROTO_FRAME_DUL(a1),d4          ; Load the fractional U step byte.
    moveq   #0,d5                          ; Clear the V step register.
    move.b  ROTO_FRAME_DVREM(a1),d5        ; Load the V fractional step byte.
    lsl.w   #8,d5                          ; Place the V fraction in the high byte.
    movea.l ROTO_FRAME_ENTRY(a1),a2        ; Load the selected family entry address.
    movea.l _TexturePackedMidHi,a1         ; Load the centered high-nibble texture table base.
    movea.l _TexturePackedMidLo,a3         ; Load the centered low-nibble texture table base.
    lea     ROTO_PLANE_BYTES(a5),a4        ; Point a4 at plane 1.
    lea     (ROTO_PLANE_BYTES*2)(a5),a6    ; Point a6 at plane 2.
    lea     (ROTO_PLANE_BYTES*3)(a5),a0    ; Point a0 at plane 3.
    jmp     (a2)                           ; Select the specialized row renderer family.

_RenderFastB0P8Entry::                      ; Entry mapped to the B0 inline V-step renderer.
_RenderFastB0U0P8Entry::                    ; Entry mapped to the B0 inline V-step renderer.
_RenderFastB0V0Entry::                      ; Entry mapped to the B0 inline V-step renderer.
_RenderFastB0U0V0Entry::                    ; Entry mapped to the B0 inline V-step renderer.
    bra.w   RF_B0_FirstRow             ; Render the first row without post-row advance.

_RenderFastBp1P8Entry::                     ; Entry mapped to the BP1 inline V-step renderer.
_RenderFastBp1U0P8Entry::                   ; Entry mapped to the BP1 inline V-step renderer.
    bra.w   RF_BP1_FirstRow             ; Render the first row without post-row advance.

_RenderFastBm1P8Entry::                     ; Entry mapped to the BM1 inline V-step renderer.
_RenderFastBm1U0P8Entry::                   ; Entry mapped to the BM1 inline V-step renderer.
    bra.w   RF_BM1_FirstRow             ; Render the first row without post-row advance.

_RenderFastBm2P8Entry::                     ; Entry mapped to the BM2 inline V-step renderer.
_RenderFastBm2U0P8Entry::                   ; Entry mapped to the BM2 inline V-step renderer.
    bra.w   RF_BM2_FirstRow             ; Render the first row without post-row advance.

RF_B0_FirstRow:                            ; Render one logical row with inline B0 V steps.
    movea.l (sp),a2            ; Reload the current row prefix pointer.
    move.l  (a2)+,(a5)+                    ; Copy prefix bytes 01-04 to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix bytes 01-04 to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix bytes 01-04 to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix bytes 01-04 to plane 3.
    move.l  (a2)+,(a5)+                    ; Copy prefix bytes 05-08 to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix bytes 05-08 to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix bytes 05-08 to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix bytes 05-08 to plane 3.
    move.l  (a2)+,(a5)+                    ; Copy prefix bytes 09-12 to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix bytes 09-12 to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix bytes 09-12 to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix bytes 09-12 to plane 3.
    move.l  (a2)+,(a5)+                    ; Copy prefix bytes 13-16 to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix bytes 13-16 to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix bytes 13-16 to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix bytes 13-16 to plane 3.
    move.b  (a2)+,(a5)+                    ; Copy prefix pair 17 to plane 0.
    move.b  (a2)+,(a4)+                    ; Copy prefix pair 17 to plane 1.
    move.b  (a2)+,(a6)+                    ; Copy prefix pair 17 to plane 2.
    move.b  (a2)+,(a0)+                    ; Copy prefix pair 17 to plane 3.
    move.l  a2,(sp)            ; Store the next row prefix pointer.
    ; Runtime pair 18.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_B0_AdvDone01                 ; Skip row increment when there is no carry.
    addi.w  #$0200,d1                      ; Apply one positive row step on carry.
RF_B0_AdvDone01:                              ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_B0_AdvDone02                 ; Skip row increment when there is no carry.
    addi.w  #$0200,d1                      ; Apply one positive row step on carry.
RF_B0_AdvDone02:                              ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 19.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_B0_AdvDone03                 ; Skip row increment when there is no carry.
    addi.w  #$0200,d1                      ; Apply one positive row step on carry.
RF_B0_AdvDone03:                              ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_B0_AdvDone04                 ; Skip row increment when there is no carry.
    addi.w  #$0200,d1                      ; Apply one positive row step on carry.
RF_B0_AdvDone04:                              ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 20.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_B0_AdvDone05                 ; Skip row increment when there is no carry.
    addi.w  #$0200,d1                      ; Apply one positive row step on carry.
RF_B0_AdvDone05:                              ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_B0_AdvDone06                 ; Skip row increment when there is no carry.
    addi.w  #$0200,d1                      ; Apply one positive row step on carry.
RF_B0_AdvDone06:                              ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 21.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_B0_AdvDone07                 ; Skip row increment when there is no carry.
    addi.w  #$0200,d1                      ; Apply one positive row step on carry.
RF_B0_AdvDone07:                              ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_B0_AdvDone08                 ; Skip row increment when there is no carry.
    addi.w  #$0200,d1                      ; Apply one positive row step on carry.
RF_B0_AdvDone08:                              ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 22.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_B0_AdvDone09                 ; Skip row increment when there is no carry.
    addi.w  #$0200,d1                      ; Apply one positive row step on carry.
RF_B0_AdvDone09:                              ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_B0_AdvDone10                 ; Skip row increment when there is no carry.
    addi.w  #$0200,d1                      ; Apply one positive row step on carry.
RF_B0_AdvDone10:                              ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 23.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_B0_AdvDone11                 ; Skip row increment when there is no carry.
    addi.w  #$0200,d1                      ; Apply one positive row step on carry.
RF_B0_AdvDone11:                              ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_B0_AdvDone12                 ; Skip row increment when there is no carry.
    addi.w  #$0200,d1                      ; Apply one positive row step on carry.
RF_B0_AdvDone12:                              ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 24.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_B0_AdvDone13                 ; Skip row increment when there is no carry.
    addi.w  #$0200,d1                      ; Apply one positive row step on carry.
RF_B0_AdvDone13:                              ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_B0_AdvDone14                 ; Skip row increment when there is no carry.
    addi.w  #$0200,d1                      ; Apply one positive row step on carry.
RF_B0_AdvDone14:                              ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 25.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_B0_AdvDone15                 ; Skip row increment when there is no carry.
    addi.w  #$0200,d1                      ; Apply one positive row step on carry.
RF_B0_AdvDone15:                              ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_B0_AdvDone16                 ; Skip row increment when there is no carry.
    addi.w  #$0200,d1                      ; Apply one positive row step on carry.
RF_B0_AdvDone16:                              ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 26.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_B0_AdvDone17                 ; Skip row increment when there is no carry.
    addi.w  #$0200,d1                      ; Apply one positive row step on carry.
RF_B0_AdvDone17:                              ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_B0_AdvDone18                 ; Skip row increment when there is no carry.
    addi.w  #$0200,d1                      ; Apply one positive row step on carry.
RF_B0_AdvDone18:                              ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 27.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_B0_AdvDone19                 ; Skip row increment when there is no carry.
    addi.w  #$0200,d1                      ; Apply one positive row step on carry.
RF_B0_AdvDone19:                              ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_B0_AdvDone20                 ; Skip row increment when there is no carry.
    addi.w  #$0200,d1                      ; Apply one positive row step on carry.
RF_B0_AdvDone20:                              ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 28.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_B0_AdvDone21                 ; Skip row increment when there is no carry.
    addi.w  #$0200,d1                      ; Apply one positive row step on carry.
RF_B0_AdvDone21:                              ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_B0_AdvDone22                 ; Skip row increment when there is no carry.
    addi.w  #$0200,d1                      ; Apply one positive row step on carry.
RF_B0_AdvDone22:                              ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
RF_B0_NextRow:                            ; Advance to the next logical row or finish.
    subq.w  #1,STACK_ROWCOUNT(sp)          ; Decrease the logical row counter.
    bpl.w   RF_B0_RowLoop              ; Render the next row if any rows remain.
    lea     STACK_TEMP_BYTES(sp),sp        ; Discard temporary renderer state.
    movem.l (sp)+,d2-d7/a2-a6              ; Restore preserved registers.
    rts                                    ; Return to C.

RF_B0_RowLoop:                          ; Start a following row after the previous row finished.
    add.b   STACK_POST_DUL_BYTE(sp),d2     ; Apply post-row fractional U delta and set X.
    move.w  STACK_POST_DUC(sp),d7          ; Load post-row integer U delta.
    addx.w  d7,d0                          ; Apply integer U delta and fractional carry.
    add.w   STACK_POST_VBASE(sp),d1        ; Apply signed post-row V base delta.
    add.w   STACK_POST_VREM(sp),d2         ; Apply post-row V fraction delta.
    bcc.w   RF_B0_FirstRow             ; Skip extra V row when there is no carry.
    addi.w  #$0200,d1                      ; Add one texture row for the post-row V carry.
    bra.w   RF_B0_FirstRow             ; Render the advanced row.

RF_BP1_FirstRow:                            ; Render one logical row with inline BP1 V steps.
    movea.l (sp),a2            ; Reload the current row prefix pointer.
    move.l  (a2)+,(a5)+                    ; Copy prefix bytes 01-04 to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix bytes 01-04 to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix bytes 01-04 to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix bytes 01-04 to plane 3.
    move.l  (a2)+,(a5)+                    ; Copy prefix bytes 05-08 to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix bytes 05-08 to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix bytes 05-08 to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix bytes 05-08 to plane 3.
    move.l  (a2)+,(a5)+                    ; Copy prefix bytes 09-12 to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix bytes 09-12 to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix bytes 09-12 to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix bytes 09-12 to plane 3.
    move.l  (a2)+,(a5)+                    ; Copy prefix bytes 13-16 to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix bytes 13-16 to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix bytes 13-16 to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix bytes 13-16 to plane 3.
    move.b  (a2)+,(a5)+                    ; Copy prefix pair 17 to plane 0.
    move.b  (a2)+,(a4)+                    ; Copy prefix pair 17 to plane 1.
    move.b  (a2)+,(a6)+                    ; Copy prefix pair 17 to plane 2.
    move.b  (a2)+,(a0)+                    ; Copy prefix pair 17 to plane 3.
    move.l  a2,(sp)            ; Store the next row prefix pointer.
    ; Runtime pair 18.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    addi.w  #$0200,d1                      ; Apply mandatory plus-one row step.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_BP1_AdvDone01                ; Skip the second row step when there is no carry.
    addi.w  #$0200,d1                      ; Apply fractional carry plus row.
RF_BP1_AdvDone01:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    addi.w  #$0200,d1                      ; Apply mandatory plus-one row step.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_BP1_AdvDone02                ; Skip the second row step when there is no carry.
    addi.w  #$0200,d1                      ; Apply fractional carry plus row.
RF_BP1_AdvDone02:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 19.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    addi.w  #$0200,d1                      ; Apply mandatory plus-one row step.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_BP1_AdvDone03                ; Skip the second row step when there is no carry.
    addi.w  #$0200,d1                      ; Apply fractional carry plus row.
RF_BP1_AdvDone03:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    addi.w  #$0200,d1                      ; Apply mandatory plus-one row step.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_BP1_AdvDone04                ; Skip the second row step when there is no carry.
    addi.w  #$0200,d1                      ; Apply fractional carry plus row.
RF_BP1_AdvDone04:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 20.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    addi.w  #$0200,d1                      ; Apply mandatory plus-one row step.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_BP1_AdvDone05                ; Skip the second row step when there is no carry.
    addi.w  #$0200,d1                      ; Apply fractional carry plus row.
RF_BP1_AdvDone05:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    addi.w  #$0200,d1                      ; Apply mandatory plus-one row step.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_BP1_AdvDone06                ; Skip the second row step when there is no carry.
    addi.w  #$0200,d1                      ; Apply fractional carry plus row.
RF_BP1_AdvDone06:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 21.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    addi.w  #$0200,d1                      ; Apply mandatory plus-one row step.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_BP1_AdvDone07                ; Skip the second row step when there is no carry.
    addi.w  #$0200,d1                      ; Apply fractional carry plus row.
RF_BP1_AdvDone07:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    addi.w  #$0200,d1                      ; Apply mandatory plus-one row step.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_BP1_AdvDone08                ; Skip the second row step when there is no carry.
    addi.w  #$0200,d1                      ; Apply fractional carry plus row.
RF_BP1_AdvDone08:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 22.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    addi.w  #$0200,d1                      ; Apply mandatory plus-one row step.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_BP1_AdvDone09                ; Skip the second row step when there is no carry.
    addi.w  #$0200,d1                      ; Apply fractional carry plus row.
RF_BP1_AdvDone09:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    addi.w  #$0200,d1                      ; Apply mandatory plus-one row step.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_BP1_AdvDone10                ; Skip the second row step when there is no carry.
    addi.w  #$0200,d1                      ; Apply fractional carry plus row.
RF_BP1_AdvDone10:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 23.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    addi.w  #$0200,d1                      ; Apply mandatory plus-one row step.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_BP1_AdvDone11                ; Skip the second row step when there is no carry.
    addi.w  #$0200,d1                      ; Apply fractional carry plus row.
RF_BP1_AdvDone11:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    addi.w  #$0200,d1                      ; Apply mandatory plus-one row step.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_BP1_AdvDone12                ; Skip the second row step when there is no carry.
    addi.w  #$0200,d1                      ; Apply fractional carry plus row.
RF_BP1_AdvDone12:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 24.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    addi.w  #$0200,d1                      ; Apply mandatory plus-one row step.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_BP1_AdvDone13                ; Skip the second row step when there is no carry.
    addi.w  #$0200,d1                      ; Apply fractional carry plus row.
RF_BP1_AdvDone13:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    addi.w  #$0200,d1                      ; Apply mandatory plus-one row step.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_BP1_AdvDone14                ; Skip the second row step when there is no carry.
    addi.w  #$0200,d1                      ; Apply fractional carry plus row.
RF_BP1_AdvDone14:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 25.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    addi.w  #$0200,d1                      ; Apply mandatory plus-one row step.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_BP1_AdvDone15                ; Skip the second row step when there is no carry.
    addi.w  #$0200,d1                      ; Apply fractional carry plus row.
RF_BP1_AdvDone15:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    addi.w  #$0200,d1                      ; Apply mandatory plus-one row step.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_BP1_AdvDone16                ; Skip the second row step when there is no carry.
    addi.w  #$0200,d1                      ; Apply fractional carry plus row.
RF_BP1_AdvDone16:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 26.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    addi.w  #$0200,d1                      ; Apply mandatory plus-one row step.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_BP1_AdvDone17                ; Skip the second row step when there is no carry.
    addi.w  #$0200,d1                      ; Apply fractional carry plus row.
RF_BP1_AdvDone17:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    addi.w  #$0200,d1                      ; Apply mandatory plus-one row step.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_BP1_AdvDone18                ; Skip the second row step when there is no carry.
    addi.w  #$0200,d1                      ; Apply fractional carry plus row.
RF_BP1_AdvDone18:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 27.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    addi.w  #$0200,d1                      ; Apply mandatory plus-one row step.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_BP1_AdvDone19                ; Skip the second row step when there is no carry.
    addi.w  #$0200,d1                      ; Apply fractional carry plus row.
RF_BP1_AdvDone19:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    addi.w  #$0200,d1                      ; Apply mandatory plus-one row step.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_BP1_AdvDone20                ; Skip the second row step when there is no carry.
    addi.w  #$0200,d1                      ; Apply fractional carry plus row.
RF_BP1_AdvDone20:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 28.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    addi.w  #$0200,d1                      ; Apply mandatory plus-one row step.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_BP1_AdvDone21                ; Skip the second row step when there is no carry.
    addi.w  #$0200,d1                      ; Apply fractional carry plus row.
RF_BP1_AdvDone21:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    addi.w  #$0200,d1                      ; Apply mandatory plus-one row step.
    add.w   d5,d2                          ; Add the fractional V step.
    bcc.s   RF_BP1_AdvDone22                ; Skip the second row step when there is no carry.
    addi.w  #$0200,d1                      ; Apply fractional carry plus row.
RF_BP1_AdvDone22:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
RF_BP1_NextRow:                            ; Advance to the next logical row or finish.
    subq.w  #1,STACK_ROWCOUNT(sp)          ; Decrease the logical row counter.
    bpl.w   RF_BP1_RowLoop              ; Render the next row if any rows remain.
    lea     STACK_TEMP_BYTES(sp),sp        ; Discard temporary renderer state.
    movem.l (sp)+,d2-d7/a2-a6              ; Restore preserved registers.
    rts                                    ; Return to C.

RF_BP1_RowLoop:                          ; Start a following row after the previous row finished.
    add.b   STACK_POST_DUL_BYTE(sp),d2     ; Apply post-row fractional U delta and set X.
    move.w  STACK_POST_DUC(sp),d7          ; Load post-row integer U delta.
    addx.w  d7,d0                          ; Apply integer U delta and fractional carry.
    add.w   STACK_POST_VBASE(sp),d1        ; Apply signed post-row V base delta.
    add.w   STACK_POST_VREM(sp),d2         ; Apply post-row V fraction delta.
    bcc.w   RF_BP1_FirstRow             ; Skip extra V row when there is no carry.
    addi.w  #$0200,d1                      ; Add one texture row for the post-row V carry.
    bra.w   RF_BP1_FirstRow             ; Render the advanced row.

RF_BM1_FirstRow:                            ; Render one logical row with inline BM1 V steps.
    movea.l (sp),a2            ; Reload the current row prefix pointer.
    move.l  (a2)+,(a5)+                    ; Copy prefix bytes 01-04 to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix bytes 01-04 to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix bytes 01-04 to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix bytes 01-04 to plane 3.
    move.l  (a2)+,(a5)+                    ; Copy prefix bytes 05-08 to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix bytes 05-08 to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix bytes 05-08 to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix bytes 05-08 to plane 3.
    move.l  (a2)+,(a5)+                    ; Copy prefix bytes 09-12 to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix bytes 09-12 to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix bytes 09-12 to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix bytes 09-12 to plane 3.
    move.l  (a2)+,(a5)+                    ; Copy prefix bytes 13-16 to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix bytes 13-16 to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix bytes 13-16 to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix bytes 13-16 to plane 3.
    move.b  (a2)+,(a5)+                    ; Copy prefix pair 17 to plane 0.
    move.b  (a2)+,(a4)+                    ; Copy prefix pair 17 to plane 1.
    move.b  (a2)+,(a6)+                    ; Copy prefix pair 17 to plane 2.
    move.b  (a2)+,(a0)+                    ; Copy prefix pair 17 to plane 3.
    move.l  a2,(sp)            ; Store the next row prefix pointer.
    ; Runtime pair 18.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM1_AdvDone01                ; Skip decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply one negative row step.
RF_BM1_AdvDone01:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM1_AdvDone02                ; Skip decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply one negative row step.
RF_BM1_AdvDone02:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 19.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM1_AdvDone03                ; Skip decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply one negative row step.
RF_BM1_AdvDone03:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM1_AdvDone04                ; Skip decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply one negative row step.
RF_BM1_AdvDone04:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 20.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM1_AdvDone05                ; Skip decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply one negative row step.
RF_BM1_AdvDone05:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM1_AdvDone06                ; Skip decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply one negative row step.
RF_BM1_AdvDone06:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 21.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM1_AdvDone07                ; Skip decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply one negative row step.
RF_BM1_AdvDone07:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM1_AdvDone08                ; Skip decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply one negative row step.
RF_BM1_AdvDone08:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 22.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM1_AdvDone09                ; Skip decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply one negative row step.
RF_BM1_AdvDone09:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM1_AdvDone10                ; Skip decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply one negative row step.
RF_BM1_AdvDone10:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 23.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM1_AdvDone11                ; Skip decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply one negative row step.
RF_BM1_AdvDone11:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM1_AdvDone12                ; Skip decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply one negative row step.
RF_BM1_AdvDone12:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 24.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM1_AdvDone13                ; Skip decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply one negative row step.
RF_BM1_AdvDone13:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM1_AdvDone14                ; Skip decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply one negative row step.
RF_BM1_AdvDone14:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 25.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM1_AdvDone15                ; Skip decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply one negative row step.
RF_BM1_AdvDone15:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM1_AdvDone16                ; Skip decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply one negative row step.
RF_BM1_AdvDone16:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 26.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM1_AdvDone17                ; Skip decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply one negative row step.
RF_BM1_AdvDone17:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM1_AdvDone18                ; Skip decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply one negative row step.
RF_BM1_AdvDone18:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 27.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM1_AdvDone19                ; Skip decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply one negative row step.
RF_BM1_AdvDone19:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM1_AdvDone20                ; Skip decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply one negative row step.
RF_BM1_AdvDone20:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 28.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM1_AdvDone21                ; Skip decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply one negative row step.
RF_BM1_AdvDone21:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM1_AdvDone22                ; Skip decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply one negative row step.
RF_BM1_AdvDone22:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
RF_BM1_NextRow:                            ; Advance to the next logical row or finish.
    subq.w  #1,STACK_ROWCOUNT(sp)          ; Decrease the logical row counter.
    bpl.w   RF_BM1_RowLoop              ; Render the next row if any rows remain.
    lea     STACK_TEMP_BYTES(sp),sp        ; Discard temporary renderer state.
    movem.l (sp)+,d2-d7/a2-a6              ; Restore preserved registers.
    rts                                    ; Return to C.

RF_BM1_RowLoop:                          ; Start a following row after the previous row finished.
    add.b   STACK_POST_DUL_BYTE(sp),d2     ; Apply post-row fractional U delta and set X.
    move.w  STACK_POST_DUC(sp),d7          ; Load post-row integer U delta.
    addx.w  d7,d0                          ; Apply integer U delta and fractional carry.
    add.w   STACK_POST_VBASE(sp),d1        ; Apply signed post-row V base delta.
    add.w   STACK_POST_VREM(sp),d2         ; Apply post-row V fraction delta.
    bcc.w   RF_BM1_FirstRow             ; Skip extra V row when there is no carry.
    addi.w  #$0200,d1                      ; Add one texture row for the post-row V carry.
    bra.w   RF_BM1_FirstRow             ; Render the advanced row.

RF_BM2_FirstRow:                            ; Render one logical row with inline BM2 V steps.
    movea.l (sp),a2            ; Reload the current row prefix pointer.
    move.l  (a2)+,(a5)+                    ; Copy prefix bytes 01-04 to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix bytes 01-04 to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix bytes 01-04 to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix bytes 01-04 to plane 3.
    move.l  (a2)+,(a5)+                    ; Copy prefix bytes 05-08 to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix bytes 05-08 to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix bytes 05-08 to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix bytes 05-08 to plane 3.
    move.l  (a2)+,(a5)+                    ; Copy prefix bytes 09-12 to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix bytes 09-12 to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix bytes 09-12 to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix bytes 09-12 to plane 3.
    move.l  (a2)+,(a5)+                    ; Copy prefix bytes 13-16 to plane 0.
    move.l  (a2)+,(a4)+                    ; Copy prefix bytes 13-16 to plane 1.
    move.l  (a2)+,(a6)+                    ; Copy prefix bytes 13-16 to plane 2.
    move.l  (a2)+,(a0)+                    ; Copy prefix bytes 13-16 to plane 3.
    move.b  (a2)+,(a5)+                    ; Copy prefix pair 17 to plane 0.
    move.b  (a2)+,(a4)+                    ; Copy prefix pair 17 to plane 1.
    move.b  (a2)+,(a6)+                    ; Copy prefix pair 17 to plane 2.
    move.b  (a2)+,(a0)+                    ; Copy prefix pair 17 to plane 3.
    move.l  a2,(sp)            ; Store the next row prefix pointer.
    ; Runtime pair 18.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    subi.w  #$0200,d1                      ; Apply the mandatory negative row step.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM2_AdvDone01                ; Skip second decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply the second negative row step.
RF_BM2_AdvDone01:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    subi.w  #$0200,d1                      ; Apply the mandatory negative row step.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM2_AdvDone02                ; Skip second decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply the second negative row step.
RF_BM2_AdvDone02:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 19.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    subi.w  #$0200,d1                      ; Apply the mandatory negative row step.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM2_AdvDone03                ; Skip second decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply the second negative row step.
RF_BM2_AdvDone03:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    subi.w  #$0200,d1                      ; Apply the mandatory negative row step.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM2_AdvDone04                ; Skip second decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply the second negative row step.
RF_BM2_AdvDone04:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 20.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    subi.w  #$0200,d1                      ; Apply the mandatory negative row step.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM2_AdvDone05                ; Skip second decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply the second negative row step.
RF_BM2_AdvDone05:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    subi.w  #$0200,d1                      ; Apply the mandatory negative row step.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM2_AdvDone06                ; Skip second decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply the second negative row step.
RF_BM2_AdvDone06:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 21.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    subi.w  #$0200,d1                      ; Apply the mandatory negative row step.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM2_AdvDone07                ; Skip second decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply the second negative row step.
RF_BM2_AdvDone07:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    subi.w  #$0200,d1                      ; Apply the mandatory negative row step.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM2_AdvDone08                ; Skip second decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply the second negative row step.
RF_BM2_AdvDone08:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 22.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    subi.w  #$0200,d1                      ; Apply the mandatory negative row step.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM2_AdvDone09                ; Skip second decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply the second negative row step.
RF_BM2_AdvDone09:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    subi.w  #$0200,d1                      ; Apply the mandatory negative row step.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM2_AdvDone10                ; Skip second decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply the second negative row step.
RF_BM2_AdvDone10:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 23.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    subi.w  #$0200,d1                      ; Apply the mandatory negative row step.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM2_AdvDone11                ; Skip second decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply the second negative row step.
RF_BM2_AdvDone11:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    subi.w  #$0200,d1                      ; Apply the mandatory negative row step.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM2_AdvDone12                ; Skip second decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply the second negative row step.
RF_BM2_AdvDone12:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 24.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    subi.w  #$0200,d1                      ; Apply the mandatory negative row step.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM2_AdvDone13                ; Skip second decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply the second negative row step.
RF_BM2_AdvDone13:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    subi.w  #$0200,d1                      ; Apply the mandatory negative row step.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM2_AdvDone14                ; Skip second decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply the second negative row step.
RF_BM2_AdvDone14:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 25.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    subi.w  #$0200,d1                      ; Apply the mandatory negative row step.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM2_AdvDone15                ; Skip second decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply the second negative row step.
RF_BM2_AdvDone15:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    subi.w  #$0200,d1                      ; Apply the mandatory negative row step.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM2_AdvDone16                ; Skip second decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply the second negative row step.
RF_BM2_AdvDone16:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 26.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    subi.w  #$0200,d1                      ; Apply the mandatory negative row step.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM2_AdvDone17                ; Skip second decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply the second negative row step.
RF_BM2_AdvDone17:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    subi.w  #$0200,d1                      ; Apply the mandatory negative row step.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM2_AdvDone18                ; Skip second decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply the second negative row step.
RF_BM2_AdvDone18:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 27.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    subi.w  #$0200,d1                      ; Apply the mandatory negative row step.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM2_AdvDone19                ; Skip second decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply the second negative row step.
RF_BM2_AdvDone19:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    subi.w  #$0200,d1                      ; Apply the mandatory negative row step.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM2_AdvDone20                ; Skip second decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply the second negative row step.
RF_BM2_AdvDone20:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
    ; Runtime pair 28.
    move.w  d0,d7                          ; Copy current U coordinate for sample 1.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    movea.w d7,a2                          ; Preserve sample 1 table offset.
    add.b   d4,d2                          ; Advance fractional U after sample 1.
    addx.w  d3,d0                          ; Advance integer U after sample 1.
    subi.w  #$0200,d1                      ; Apply the mandatory negative row step.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM2_AdvDone21                ; Skip second decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply the second negative row step.
RF_BM2_AdvDone21:                             ; Continue after the inline V step.
    move.w  d0,d7                          ; Copy current U coordinate for sample 2.
    andi.w  #$01FC,d7                      ; Wrap U to a 128-pixel texture byte offset.
    add.w   d1,d7                          ; Add the wrapped V row offset.
    move.l  (a3,d7.w),d7                   ; Fetch the low-nibble contribution for sample 2.
    add.b   d4,d2                          ; Advance fractional U after sample 2.
    addx.w  d3,d0                          ; Advance integer U after sample 2.
    subi.w  #$0200,d1                      ; Apply the mandatory negative row step.
    add.w   d5,d2                          ; Add the negative fractional V step.
    bcs.s   RF_BM2_AdvDone22                ; Skip second decrement when the add carried.
    subi.w  #$0200,d1                      ; Apply the second negative row step.
RF_BM2_AdvDone22:                             ; Continue after the inline V step.
    or.l    (a1,a2.w),d7                   ; Merge the sample 1 high-nibble contribution.
    move.b  d7,(a5)+                       ; Store the plane 0 pair byte.
    swap    d7                             ; Move the plane 2 byte into the low byte.
    move.b  d7,(a6)+                       ; Store the plane 2 pair byte.
    lsr.l   #8,d7                          ; Move the plane 3 byte into the low byte.
    move.b  d7,(a0)+                       ; Store the plane 3 pair byte.
    swap    d7                             ; Move the plane 1 byte into the low byte.
    move.b  d7,(a4)+                       ; Store the plane 1 pair byte.
RF_BM2_NextRow:                            ; Advance to the next logical row or finish.
    subq.w  #1,STACK_ROWCOUNT(sp)          ; Decrease the logical row counter.
    bpl.w   RF_BM2_RowLoop              ; Render the next row if any rows remain.
    lea     STACK_TEMP_BYTES(sp),sp        ; Discard temporary renderer state.
    movem.l (sp)+,d2-d7/a2-a6              ; Restore preserved registers.
    rts                                    ; Return to C.

RF_BM2_RowLoop:                          ; Start a following row after the previous row finished.
    add.b   STACK_POST_DUL_BYTE(sp),d2     ; Apply post-row fractional U delta and set X.
    move.w  STACK_POST_DUC(sp),d7          ; Load post-row integer U delta.
    addx.w  d7,d0                          ; Apply integer U delta and fractional carry.
    add.w   STACK_POST_VBASE(sp),d1        ; Apply signed post-row V base delta.
    add.w   STACK_POST_VREM(sp),d2         ; Apply post-row V fraction delta.
    bcc.w   RF_BM2_FirstRow             ; Skip extra V row when there is no carry.
    addi.w  #$0200,d1                      ; Add one texture row for the post-row V carry.
    bra.w   RF_BM2_FirstRow             ; Render the advanced row.

