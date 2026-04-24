;**********************************************************************
;* 4x4 HAM7 Rotozoomer                                                *
;*                                                                    *
;* 4 DMA bitplanes, HAM control via BPL5DAT/BPL6DAT, 80 columns      *
;* Amiga 500 OCS, 68000                                               *
;*                                                                    *
;* Assembler hotloop for the affine sampler and HAM planar emitter.   *
;**********************************************************************

    machine 68000

    include "lwmf/lwmf_hardware_regs.i"

ROTO_ROWS            equ 48
ROTO_PAIR_COUNT      equ 40
ROTO_LOOP_COUNT      equ (ROTO_PAIR_COUNT/2)
ROTO_ROW_ADVANCE     equ ((BYTESPERROW*NUMBEROFBITPLANES)-ROTO_PAIR_COUNT)
HAM_EXPAND_BLOCKSIZE equ 8192

; -----------------------------------------------------------------------------
; RotoAsmParams structure offsets
; -----------------------------------------------------------------------------

RA_Texture equ 0
RA_Dest    equ 4
RA_Expand  equ 8
RA_RowU    equ 12
RA_RowV    equ 14
RA_DuDx    equ 16
RA_DvDx    equ 18
RA_DuDy    equ 20
RA_DvDy    equ 22

; -----------------------------------------------------------------------------
; Local stack offsets
; -----------------------------------------------------------------------------

LOC_RowStepU equ 0
LOC_RowStepV equ 2
LOC_RowCount equ 4

; -----------------------------------------------------------------------------
; PROCESS_PAIR
;
; Input:
; d0 = U in 8.8 fixed point
; d1 = V in 8.8 fixed point
; a1 = texture base (128x128, UWORD texels)
; a2 = HAM expand hi01 table
; a3 = HAM expand lo01 table
; a4 = HAM expand hi23 table
; a6 = HAM expand lo23 table
; a5 = current destination byte position
; d4 = DuDx
; d5 = DvDx
;
; Clobbers:
; d2, d3, d7
; -----------------------------------------------------------------------------

PROCESS_PAIR macro
    move.w  d1,d7
    andi.w  #$7F00,d7
    move.w  d0,d2
    lsr.w   #8,d2
    andi.w  #$007F,d2
    add.w   d2,d2
    add.w   d2,d7
    move.w  (a1,d7.w),d2
    add.w   d4,d0
    add.w   d5,d1

    move.w  d1,d7
    andi.w  #$7F00,d7
    move.w  d0,d3
    lsr.w   #8,d3
    andi.w  #$007F,d3
    add.w   d3,d3
    add.w   d3,d7
    move.w  (a1,d7.w),d7
    add.w   d4,d0
    add.w   d5,d1

    add.w   d2,d2
    add.w   d7,d7

    move.w  (a2,d2.w),d3
    or.w    (a3,d7.w),d3
    move.w  (a4,d2.w),d2
    or.w    (a6,d7.w),d2

    move.b  d3,(a5)
    lsr.w   #8,d3
    move.b  d3,BYTESPERROW(a5)
    move.b  d2,(BYTESPERROW*2)(a5)
    lsr.w   #8,d2
    move.b  d2,(BYTESPERROW*3)(a5)
    addq.l  #1,a5
endm

; -----------------------------------------------------------------------------
; void DrawRotoBodyAsm(__reg("a0") const struct RotoAsmParams *Params)
; -----------------------------------------------------------------------------

_DrawRotoBodyAsm::
    movem.l d2-d7/a1-a6,-(sp)
    lea     -6(sp),sp

    movea.l RA_Texture(a0),a1
    movea.l RA_Dest(a0),a5
    movea.l RA_Expand(a0),a2
    lea     HAM_EXPAND_BLOCKSIZE(a2),a3
    lea     (HAM_EXPAND_BLOCKSIZE*2)(a2),a4
    lea     (HAM_EXPAND_BLOCKSIZE*3)(a2),a6

    move.w  RA_DuDx(a0),d4
    move.w  RA_DvDx(a0),d5
    move.w  RA_RowU(a0),d0
    move.w  RA_RowV(a0),d1

    move.w  #ROTO_ROWS-1,LOC_RowCount(sp)

    move.w  d4,d7
    lsl.w   #6,d7
    move.w  d4,d2
    lsl.w   #4,d2
    add.w   d2,d7
    neg.w   d7
    add.w   RA_DuDy(a0),d7
    move.w  d7,LOC_RowStepU(sp)

    move.w  d5,d7
    lsl.w   #6,d7
    move.w  d5,d2
    lsl.w   #4,d2
    add.w   d2,d7
    neg.w   d7
    add.w   RA_DvDy(a0),d7
    move.w  d7,LOC_RowStepV(sp)

.row_loop:
    moveq   #ROTO_LOOP_COUNT-1,d6

.pair_loop:
    PROCESS_PAIR
    PROCESS_PAIR
    dbra    d6,.pair_loop

    add.w   LOC_RowStepU(sp),d0
    add.w   LOC_RowStepV(sp),d1
    adda.w  #ROTO_ROW_ADVANCE,a5

    subq.w  #1,LOC_RowCount(sp)
    bpl.w   .row_loop

    lea     6(sp),sp
    movem.l (sp)+,d2-d7/a1-a6
    rts
