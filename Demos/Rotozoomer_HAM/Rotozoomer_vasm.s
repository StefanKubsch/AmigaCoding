;**********************************************************************
;* 4x4 HAM7 Rotozoomer                                                *
;*                                                                    *
;* 4 DMA bitplanes, HAM control via BPL5DAT/BPL6DAT, 80 columns      *
;* Amiga 500 OCS, 68000                                               *
;*                                                                    *
;* Assembler hotloop for the affine sampler and HAM planar emitter.   *
;**********************************************************************

    machine 68000                         ; Assemble for a plain Motorola 68000.

    include "lwmf/lwmf_hardware_regs.i"   ; Import hardware-related constants such as BYTESPERROW and NUMBEROFBITPLANES.

ROTO_ROWS            equ 48               ; Number of logical roto rows rendered by the CPU.
ROTO_PAIR_COUNT      equ 40               ; Number of texel pairs processed per row (80 columns / 2).
ROTO_ROW_ADVANCE     equ ((BYTESPERROW*NUMBEROFBITPLANES)-ROTO_PAIR_COUNT) ; Advance from the end of one rendered row to the next within the interleaved bitmap.

; -----------------------------------------------------------------------------
; RotoAsmParams structure offsets
; -----------------------------------------------------------------------------

RA_Texture  equ 0                         ; Offset of Params->Texture.
RA_Dest     equ 4                         ; Offset of Params->Dest.
RA_RowU     equ 8                         ; Offset of Params->RowU.
RA_RowV     equ 10                        ; Offset of Params->RowV.
RA_DuDx     equ 12                        ; Offset of Params->DuDx.
RA_DvDx     equ 14                        ; Offset of Params->DvDx.
RA_RowStepU equ 16                        ; Offset of Params->RowStepU.
RA_RowStepV equ 18                        ; Offset of Params->RowStepV.

; -----------------------------------------------------------------------------
; PROCESS_PAIR
;
; Input:
; d0 = U in 8.8 fixed point
; d1 = V in 8.8 fixed point
; a1 = packed texture midpoint (128x128, ULONG texels, base biased by +$8000)
; a5 = plane 0 destination byte
; a4 = plane 1 destination byte
; a6 = plane 2 destination byte
; a0 = plane 3 destination byte
; d4 = DuDx
; d5 = DvDx
;
; Clobbers:
; d2, d3, d7
; -----------------------------------------------------------------------------

PROCESS_PAIR macro                        ; Process two logical texels and emit one byte into each of the four data bitplanes.
    move.w  d1,d7                         ; Copy V to a temporary index register.
    andi.w  #$7F00,d7                     ; Keep V's integer 7-bit texel row component (wrap to 0..127).
    add.w   d7,d7                         ; Multiply row index by 2 so it becomes a 512-byte row stride contribution.
    move.w  d0,d2                         ; Copy U to a temporary register.
    lsr.w   #6,d2                         ; Convert 8.8 U to a 4-byte texel offset domain.
    andi.w  #$01FC,d2                     ; Keep the aligned byte offset inside one 128-texel row.
    add.w   d2,d7                         ; Combine V row offset and U texel offset into one texture byte offset.
    eori.w  #$8000,d7                     ; Bias the unsigned 0..65532 offset into signed word index space around TextureMid.
    move.l  (a1,d7.w),d2                  ; Fetch packed contribution for the first texel of the pair.
    add.w   d4,d0                         ; Advance U by DuDx to the second texel.
    add.w   d5,d1                         ; Advance V by DvDx to the second texel.

    move.w  d1,d7                         ; Copy updated V for the second texel.
    andi.w  #$7F00,d7                     ; Keep V's wrapped integer row bits for the second sample.
    add.w   d7,d7                         ; Convert that row index to a 512-byte row contribution.
    move.w  d0,d3                         ; Copy updated U for the second texel.
    lsr.w   #6,d3                         ; Convert U into a packed-texture byte offset contribution.
    andi.w  #$01FC,d3                     ; Keep only the aligned offset inside the current texture row.
    add.w   d3,d7                         ; Form the final packed-texture offset for texel two.
    eori.w  #$8000,d7                     ; Apply the midpoint bias again for signed indexed addressing.
    move.l  (a1,d7.w),d3                  ; Fetch packed contribution for the second texel.
    add.w   d4,d0                         ; Advance U to the next pair's first texel.
    add.w   d5,d1                         ; Advance V to the next pair's first texel.

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
; void DrawRotoBodyAsm(__reg("a0") const struct RotoAsmParams *Params)
; -----------------------------------------------------------------------------

_DrawRotoBodyAsm::                        ; Entry point called from C with Params in A0.
    movem.l d2-d7/a1-a6,-(sp)             ; Save all registers used by the routine.

    movea.l a0,a3                         ; Keep Params in A3 for repeated field access.
    movea.l RA_Texture(a3),a1             ; Load pointer to the packed texture midpoint.
    movea.l RA_Dest(a3),a5                ; Load destination pointer for plane 0.

    move.w  RA_DuDx(a3),d4                ; Load horizontal U delta.
    move.w  RA_DvDx(a3),d5                ; Load horizontal V delta.
    move.w  RA_RowU(a3),d0                ; Load starting U for the first row.
    move.w  RA_RowV(a3),d1                ; Load starting V for the first row.
    moveq   #ROTO_ROWS-1,d6               ; Set DBRA loop counter for all 48 rows.

    lea     BYTESPERROW(a5),a4            ; Plane 1 starts one bitplane stride after plane 0.
    lea     (BYTESPERROW*2)(a5),a6        ; Plane 2 starts two bitplane strides after plane 0.
    lea     (BYTESPERROW*3)(a5),a0        ; Plane 3 starts three bitplane strides after plane 0.

.row_loop:                                ; Start of one logical output row.
    PROCESS_PAIR                          ; Process texel pair  1 of 40.
    PROCESS_PAIR                          ; Process texel pair  2 of 40.
    PROCESS_PAIR                          ; Process texel pair  3 of 40.
    PROCESS_PAIR                          ; Process texel pair  4 of 40.
    PROCESS_PAIR                          ; Process texel pair  5 of 40.
    PROCESS_PAIR                          ; Process texel pair  6 of 40.
    PROCESS_PAIR                          ; Process texel pair  7 of 40.
    PROCESS_PAIR                          ; Process texel pair  8 of 40.
    PROCESS_PAIR                          ; Process texel pair  9 of 40.
    PROCESS_PAIR                          ; Process texel pair 10 of 40.
    PROCESS_PAIR                          ; Process texel pair 11 of 40.
    PROCESS_PAIR                          ; Process texel pair 12 of 40.
    PROCESS_PAIR                          ; Process texel pair 13 of 40.
    PROCESS_PAIR                          ; Process texel pair 14 of 40.
    PROCESS_PAIR                          ; Process texel pair 15 of 40.
    PROCESS_PAIR                          ; Process texel pair 16 of 40.
    PROCESS_PAIR                          ; Process texel pair 17 of 40.
    PROCESS_PAIR                          ; Process texel pair 18 of 40.
    PROCESS_PAIR                          ; Process texel pair 19 of 40.
    PROCESS_PAIR                          ; Process texel pair 20 of 40.
    PROCESS_PAIR                          ; Process texel pair 21 of 40.
    PROCESS_PAIR                          ; Process texel pair 22 of 40.
    PROCESS_PAIR                          ; Process texel pair 23 of 40.
    PROCESS_PAIR                          ; Process texel pair 24 of 40.
    PROCESS_PAIR                          ; Process texel pair 25 of 40.
    PROCESS_PAIR                          ; Process texel pair 26 of 40.
    PROCESS_PAIR                          ; Process texel pair 27 of 40.
    PROCESS_PAIR                          ; Process texel pair 28 of 40.
    PROCESS_PAIR                          ; Process texel pair 29 of 40.
    PROCESS_PAIR                          ; Process texel pair 30 of 40.
    PROCESS_PAIR                          ; Process texel pair 31 of 40.
    PROCESS_PAIR                          ; Process texel pair 32 of 40.
    PROCESS_PAIR                          ; Process texel pair 33 of 40.
    PROCESS_PAIR                          ; Process texel pair 34 of 40.
    PROCESS_PAIR                          ; Process texel pair 35 of 40.
    PROCESS_PAIR                          ; Process texel pair 36 of 40.
    PROCESS_PAIR                          ; Process texel pair 37 of 40.
    PROCESS_PAIR                          ; Process texel pair 38 of 40.
    PROCESS_PAIR                          ; Process texel pair 39 of 40.
    PROCESS_PAIR                          ; Process texel pair 40 of 40.

    add.w   RA_RowStepU(a3),d0            ; Move U from the end of this row to the start of the next row.
    add.w   RA_RowStepV(a3),d1            ; Move V from the end of this row to the start of the next row.
    adda.w  #ROTO_ROW_ADVANCE,a5          ; Advance plane 0 pointer to the next logical row start.
    adda.w  #ROTO_ROW_ADVANCE,a4          ; Advance plane 1 pointer to the next logical row start.
    adda.w  #ROTO_ROW_ADVANCE,a6          ; Advance plane 2 pointer to the next logical row start.
    adda.w  #ROTO_ROW_ADVANCE,a0          ; Advance plane 3 pointer to the next logical row start.

    dbra    d6,.row_loop                  ; Repeat until all rows have been rendered.

    movem.l (sp)+,d2-d7/a1-a6             ; Restore saved registers.
    rts                                   ; Return to the C caller.
