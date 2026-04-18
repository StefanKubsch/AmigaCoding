; -----------------------------------------------------------------------------
; Rotozoomer drawing routine
; Amiga 500 OCS / 68000 - vasm Motorola syntax
;
; Key idea
; --------
; The inner loop advances U/V for every sampled texel.
; One row emits 48 logical pixels, so after one full row:
;   d0 = RowU + 48 * DuDx
;   d1 = RowV + 48 * DvDx
; To reach the next row start directly, add these precomputed corrections:
;   RowStepU = DuDy - 48 * DuDx
;   RowStepV = DvDy - 48 * DvDx
;
; (C) 2026 by Stefan Kubsch
; -----------------------------------------------------------------------------

	machine 68000                        ; assemble for Motorola 68000

	include "lwmf/lwmf_hardware_regs.i"  ; import bitmap layout constants such as BYTESPERROW

; -----------------------------------------------------------------------------
; Effect dimensions
; -----------------------------------------------------------------------------
ROTO_ROWS        equ 48                 ; render 48 logical rows
ROTO_LOOP_COUNT  equ 12                 ; 12 iterations * 2 pairs = 24 packed pairs = 48 pixels

; -----------------------------------------------------------------------------
; struct RotoAsmParams layout
; Must match the C struct exactly.
; -----------------------------------------------------------------------------
RA_Texture       equ  0                 ; const UBYTE *Texture
RA_RowPtr        equ  4                 ; UBYTE **RowPtr
RA_Expand        equ  8                 ; const UBYTE *PairExpand
RA_RowU          equ 12                 ; WORD RowU
RA_RowV          equ 14                 ; WORD RowV
RA_DuDx          equ 16                 ; WORD DuDx
RA_DvDx          equ 18                 ; WORD DvDx
RA_DuDy          equ 20                 ; WORD DuDy
RA_DvDy          equ 22                 ; WORD DvDy

; -----------------------------------------------------------------------------
; Local stack layout after "lea -6(sp),sp"
; -----------------------------------------------------------------------------
LOC_RowCount     equ 0                  ; WORD remaining row counter
LOC_RowStepU     equ 2                  ; WORD correction added to d0 after each row
LOC_RowStepV     equ 4                  ; WORD correction added to d1 after each row

; -----------------------------------------------------------------------------
; PROCESS_PAIR
;
; Builds one packed 2-pixel key from two texture samples and writes the
; resulting bytes to all 5 bitplanes.
;
; Input:
;   d0 = U in 8.8 fixed point
;   d1 = V in 8.8 fixed point
;   a1 = texture base
;   a2 = plane 0/1 word table base
;   a3 = plane 2/3 word table base
;   a4 = plane 4 byte table base
;   a5 = current destination byte position
;   d4 = DuDx
;   d5 = DvDx
;
; Clobbers:
;   d2, d3, d7
; -----------------------------------------------------------------------------
PROCESS_PAIR macro
	move.w  d1,d7                          ; copy V so we can derive the texture row offset
	andi.w  #$7F00,d7                      ; keep integer Y bits already aligned as texY*256
	move.w  d0,d3                          ; copy U so we can derive integer X
	lsr.w   #8,d3                          ; convert U from 8.8 fixed point to integer texX
	add.w   d3,d7                          ; build texture index = texY*256 + texX
	move.b  (a1,d7.w),d2                   ; read first texel c0 from the texture
	andi.w  #$00FF,d2                      ; zero-extend unsigned texel c0 to word
	add.w   d4,d0                          ; advance U to the next sample position
	add.w   d5,d1                          ; advance V to the next sample position

	move.w  d1,d7                          ; copy updated V for the second texel sample
	andi.w  #$7F00,d7                      ; keep integer Y bits already aligned as texY*256
	move.w  d0,d3                          ; copy updated U so we can derive integer X
	lsr.w   #8,d3                          ; convert updated U to integer texX
	add.w   d3,d7                          ; build texture index for the second sample
	move.b  (a1,d7.w),d7                   ; read second texel c1 from the texture
	andi.w  #$00FF,d7                      ; zero-extend unsigned texel c1 to word
	lsl.w   #5,d7                          ; move c1 into bits 5..9 of the packed key
	or.w    d2,d7                          ; combine c0 and c1 into one 10-bit packed pair key
	add.w   d4,d0                          ; advance U to the next pair start
	add.w   d5,d1                          ; advance V to the next pair start

	move.b  (a4,d7.w),(BYTESPERROW*4)(a5)  ; write plane 4 byte directly from the byte lookup table
	add.w   d7,d7                          ; scale packed key by 2 for the word lookup tables
	move.w  (a2,d7.w),d2                   ; load packed output bytes for planes 0 and 1
	move.w  (a3,d7.w),d3                   ; load packed output bytes for planes 2 and 3
	move.b  d2,(a5)                        ; write plane 0 byte
	lsr.w   #8,d2                          ; move plane 1 byte into the low byte position
	move.b  d2,BYTESPERROW(a5)             ; write plane 1 byte
	move.b  d3,(BYTESPERROW*2)(a5)         ; write plane 2 byte
	lsr.w   #8,d3                          ; move plane 3 byte into the low byte position
	move.b  d3,(BYTESPERROW*3)(a5)         ; write plane 3 byte
	addq.l  #1,a5                          ; advance destination pointer to the next packed pair slot
	endm                                   ; end PROCESS_PAIR

; -----------------------------------------------------------------------------
; void DrawRotoBodyAsm(__reg("a0") const struct RotoAsmParams *Params)
; -----------------------------------------------------------------------------
_DrawRotoBodyAsm::
	movem.l d2-d7/a1-a6,-(sp)              ; save all registers used by this routine
	lea     -6(sp),sp                      ; reserve 6 bytes for local variables

	movea.l RA_Texture(a0),a1              ; load texture base pointer
	movea.l RA_RowPtr(a0),a6               ; load pointer to the per-row destination pointer list
	movea.l RA_Expand(a0),a2               ; load base of the contiguous PairExpand block
	lea     2048(a2),a3                    ; split out plane 2/3 word table base
	lea     4096(a2),a4                    ; split out plane 4 byte table base

	move.w  RA_DuDx(a0),d4                 ; load horizontal U step
	move.w  RA_DvDx(a0),d5                 ; load horizontal V step
	move.w  RA_RowU(a0),d0                 ; load initial row-start U once
	move.w  RA_RowV(a0),d1                 ; load initial row-start V once
	move.w  #ROTO_ROWS-1,LOC_RowCount(sp)  ; initialize outer row counter

	move.w  d4,d7                          ; copy DuDx to build 48*DuDx
	lsl.w   #5,d7                          ; d7 = 32 * DuDx
	move.w  d4,d2                          ; copy DuDx again to build the remaining 16*DuDx
	lsl.w   #4,d2                          ; d2 = 16 * DuDx
	add.w   d2,d7                          ; d7 = 48 * DuDx
	neg.w   d7                             ; d7 = -48 * DuDx
	add.w   RA_DuDy(a0),d7                 ; d7 = DuDy - 48 * DuDx
	move.w  d7,LOC_RowStepU(sp)            ; store end-of-row U correction

	move.w  d5,d7                          ; copy DvDx to build 48*DvDx
	lsl.w   #5,d7                          ; d7 = 32 * DvDx
	move.w  d5,d2                          ; copy DvDx again to build the remaining 16*DvDx
	lsl.w   #4,d2                          ; d2 = 16 * DvDx
	add.w   d2,d7                          ; d7 = 48 * DvDx
	neg.w   d7                             ; d7 = -48 * DvDx
	add.w   RA_DvDy(a0),d7                 ; d7 = DvDy - 48 * DvDx
	move.w  d7,LOC_RowStepV(sp)            ; store end-of-row V correction

.row_loop:
	movea.l (a6)+,a5                        ; fetch destination pointer for this row
	moveq   #ROTO_LOOP_COUNT-1,d6           ; initialize inner loop for 24 packed pairs

.pair_loop:
	PROCESS_PAIR                            ; process first packed pair of this iteration
	PROCESS_PAIR                            ; process second packed pair of this iteration
	dbra    d6,.pair_loop                   ; continue until 24 packed pairs are emitted

	add.w   LOC_RowStepU(sp),d0             ; convert end-of-row U into next row-start U
	add.w   LOC_RowStepV(sp),d1             ; convert end-of-row V into next row-start V
	subq.w  #1,LOC_RowCount(sp)             ; decrement remaining row counter
	bpl.w   .row_loop                       ; continue while rows remain

	lea     6(sp),sp                        ; release local stack storage
	movem.l (sp)+,d2-d7/a1-a6               ; restore saved registers
	rts                                     ; return to the C caller
