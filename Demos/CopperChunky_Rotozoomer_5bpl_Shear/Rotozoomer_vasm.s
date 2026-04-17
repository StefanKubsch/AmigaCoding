; -----------------------------------------------------------------------------
; Final chunky-to-bitplane packer for the Rocklobster-inspired shear rotozoomer
; Amiga 500 OCS / 68000 - vasm Motorola syntax
;
; The heavy lifting (pre-rotated textures + two-pass shear pipeline) happens in
; C now. This routine only converts the already rendered 48x48 chunky image back
; into the existing 4x4 copper-chunky bitplane format.
;
; One chunky row contains 48 logical pixels. Two logical pixels become one byte
; per bitplane by means of the PairExpand lookup tables.
;
; (C) 2026 by Stefan Kubsch / Deep4
; Reworked to a shear pipeline by OpenAI
; -----------------------------------------------------------------------------

    machine 68000

    include "lwmf/lwmf_hardware_regs.i"

; -----------------------------------------------------------------------------
; Effect dimensions
; -----------------------------------------------------------------------------
ROTO_ROWS        equ 48
ROTO_PAIR_COUNT  equ 24

; -----------------------------------------------------------------------------
; struct RotoAsmParams layout
; Must match the C struct exactly.
; -----------------------------------------------------------------------------
RA_Chunky        equ  0
RA_RowPtr        equ  4
RA_Expand        equ  8

; -----------------------------------------------------------------------------
; PACK_PAIR
;
; Reads two chunky pixels, builds the 10-bit pair key and writes the resulting
; bytes to all 5 bitplanes using the same PairExpand layout as the original
; direct affine renderer.
;
; Input:
;   a1 = current chunky source pointer
;   a2 = plane 0/1 word table base
;   a3 = plane 2/3 word table base
;   a4 = plane 4 byte table base
;   a5 = current destination byte position
;
; Clobbers:
;   d0-d3
; -----------------------------------------------------------------------------
PACK_PAIR macro
    moveq   #0,d0
    move.b  (a1)+,d0
    moveq   #0,d1
    move.b  (a1)+,d1
    lsl.w   #5,d1
    or.w    d0,d1

    move.b  (a4,d1.w),(BYTESPERROW*4)(a5)
    add.w   d1,d1
    move.w  (a2,d1.w),d2
    move.w  (a3,d1.w),d3
    move.b  d2,(a5)
    lsr.w   #8,d2
    move.b  d2,BYTESPERROW(a5)
    move.b  d3,(BYTESPERROW*2)(a5)
    lsr.w   #8,d3
    move.b  d3,(BYTESPERROW*3)(a5)
    addq.l  #1,a5
    endm

; -----------------------------------------------------------------------------
; void DrawRotoBodyAsm(__reg("a0") const struct RotoAsmParams *Params)
; -----------------------------------------------------------------------------
_DrawRotoBodyAsm::
    movem.l d2-d7/a1-a6,-(sp)

    movea.l RA_Chunky(a0),a1
    movea.l RA_RowPtr(a0),a6
    movea.l RA_Expand(a0),a2
    lea     2048(a2),a3
    lea     4096(a2),a4

    moveq   #ROTO_ROWS-1,d7
.row_loop:
    movea.l (a6)+,a5
    moveq   #ROTO_PAIR_COUNT-1,d6
.pair_loop:
    PACK_PAIR
    dbra    d6,.pair_loop
    dbra    d7,.row_loop

    movem.l (sp)+,d2-d7/a1-a6
    rts
