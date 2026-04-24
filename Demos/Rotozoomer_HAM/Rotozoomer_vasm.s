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
ROTO_ROW_ADVANCE     equ ((BYTESPERROW*NUMBEROFBITPLANES)-ROTO_PAIR_COUNT)

; -----------------------------------------------------------------------------
; RotoAsmParams structure offsets
; -----------------------------------------------------------------------------

RA_Texture  equ 0
RA_Dest     equ 4
RA_RowU     equ 8
RA_RowV     equ 10
RA_DuDx     equ 12
RA_DvDx     equ 14
RA_RowStepU equ 16
RA_RowStepV equ 18

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

PROCESS_PAIR macro
    move.w  d1,d7
    andi.w  #$7F00,d7
    add.w   d7,d7
    move.w  d0,d2
    lsr.w   #6,d2
    andi.w  #$01FC,d2
    add.w   d2,d7
    eori.w  #$8000,d7
    move.l  (a1,d7.w),d2
    add.w   d4,d0
    add.w   d5,d1

    move.w  d1,d7
    andi.w  #$7F00,d7
    add.w   d7,d7
    move.w  d0,d3
    lsr.w   #6,d3
    andi.w  #$01FC,d3
    add.w   d3,d7
    eori.w  #$8000,d7
    move.l  (a1,d7.w),d3
    add.w   d4,d0
    add.w   d5,d1

    lsr.l   #4,d3
    or.l    d3,d2

    move.b  d2,(a5)+
    lsr.w   #8,d2
    move.b  d2,(a4)+
    swap    d2
    move.b  d2,(a6)+
    lsr.w   #8,d2
    move.b  d2,(a0)+
endm

; -----------------------------------------------------------------------------
; void DrawRotoBodyAsm(__reg("a0") const struct RotoAsmParams *Params)
; -----------------------------------------------------------------------------

_DrawRotoBodyAsm::
    movem.l d2-d7/a1-a6,-(sp)

    movea.l a0,a3
    movea.l RA_Texture(a3),a1
    movea.l RA_Dest(a3),a5

    move.w  RA_DuDx(a3),d4
    move.w  RA_DvDx(a3),d5
    move.w  RA_RowU(a3),d0
    move.w  RA_RowV(a3),d1
    moveq   #ROTO_ROWS-1,d6

    lea     BYTESPERROW(a5),a4
    lea     (BYTESPERROW*2)(a5),a6
    lea     (BYTESPERROW*3)(a5),a0

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

    add.w   RA_RowStepU(a3),d0
    add.w   RA_RowStepV(a3),d1
    adda.w  #ROTO_ROW_ADVANCE,a5
    adda.w  #ROTO_ROW_ADVANCE,a4
    adda.w  #ROTO_ROW_ADVANCE,a6
    adda.w  #ROTO_ROW_ADVANCE,a0

    dbra    d6,.row_loop

    movem.l (sp)+,d2-d7/a1-a6
    rts
