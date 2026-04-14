; -----------------------------------------------------------------------------
; Rotozoomer drawing routine
; Amiga 500 OCS / 68000 - vasm Motorola syntax
;
; High-level idea
; ---------------
; - The effect renders a 48 x 48 logical chunky image.
; - Each logical pixel becomes a 4 x 4 block on screen.
; - Two neighboring logical pixels are packed into one planar byte position.
; - A lookup table expands that packed 2-pixel value into 5 bitplane bytes.
; - Texture coordinates are sampled in 8.8 fixed point.
; - U and V are advanced affinely:
;       across a row with DuDx / DvDx
;       to the next row with DuDy / DvDy
;
; ----------------------------------------------------
; - The texture is stored internally as 256 x 128 bytes.
;   Each original 128-byte source row is duplicated horizontally.
;   That lets the hotloop build the texture index more cheaply:
;       texIndex = ((V >> 8) & 127) * 256 + ((U >> 8) & 255)
;   which is implemented as:
;       (V & $7F00) + (U >> 8)
; - The C side provides one destination pointer per logical output row.
;   This removes ScreenBase + RowOffset address synthesis from the hotloop.
; - The packed-pair expansion uses 3 table reads per pair:
;       plane 0/1 as one word table
;       plane 2/3 as one word table
;       plane 4  as one byte table
;
; PairExpand memory layout
; ------------------------
; Params->PairExpand points to one contiguous 5120-byte block:
;   offset 0    .. 2047 : 1024 WORD entries for planes 0 and 1
;   offset 2048 .. 4095 : 1024 WORD entries for planes 2 and 3
;   offset 4096 .. 5119 : 1024 BYTE entries for plane 4
;
; One packed pair value uses 10 bits:
;   packed = c0 | (c1 << 5)
; where c0 and c1 are 5-bit chunky color indices.
;
; (C) 2026 by Stefan Kubsch
; -----------------------------------------------------------------------------

	machine 68000

	include "lwmf/lwmf_hardware_regs.i"

; -----------------------------------------------------------------------------
; Effect dimensions
; -----------------------------------------------------------------------------
ROTO_ROWS        equ 48                  ; 48 logical rows are rendered
ROTO_LOOP_COUNT  equ 12                  ; 12 iterations * 2 pairs = 24 pairs
                                         ; 24 pairs * 2 pixels = 48 logical pixels

; -----------------------------------------------------------------------------
; struct RotoAsmParams layout
; Must match the C struct exactly.
; -----------------------------------------------------------------------------
RA_Texture        equ  0                 ; const UBYTE *Texture
RA_RowPtr         equ  4                 ; UBYTE **RowPtr
RA_Expand         equ  8                 ; const UBYTE *PairExpand
RA_RowU           equ 12                 ; WORD RowU
RA_RowV           equ 14                 ; WORD RowV
RA_DuDx           equ 16                 ; WORD DuDx
RA_DvDx           equ 18                 ; WORD DvDx
RA_DuDy           equ 20                 ; WORD DuDy
RA_DvDy           equ 22                 ; WORD DvDy

; -----------------------------------------------------------------------------
; void DrawRotoBodyAsm(__reg("a0") const struct RotoAsmParams *Params)
;
; Register map
; ------------
; a0 = Params pointer during setup only
; a1 = Texture base pointer (256 x 128 internal chunky texture)
; a2 = PairExpand plane 0/1 word table base
; a3 = PairExpand plane 2/3 word table base
; a4 = PairExpand plane 4 byte table base
; a5 = destination pointer for the current logical row, plane 0 base
; a6 = RowPtr cursor, advanced once per logical row
;
; d0 = current U in 8.8 fixed point
; d1 = current V in 8.8 fixed point
; d2 = first texel of the current packed pair (c0), later plane 0/1 word
; d3 = scratch register, usually texX or plane 2/3 word
; d4 = DuDx
; d5 = DvDx
; d6 = inner loop counter
; d7 = scratch / texture index / packed pair index
;
; Stack locals after "lea -12(sp),sp"
; -----------------------------------
;   (sp)   = outer row counter
;   2(sp)  = DuDy
;   4(sp)  = DvDy
;   6(sp)  = RowU for the current / next row
;   8(sp)  = RowV for the current / next row
;
; Output mapping
; --------------
; For each packed pair:
;   - one byte is written to plane 0
;   - one byte is written to plane 1
;   - one byte is written to plane 2
;   - one byte is written to plane 3
;   - one byte is written to plane 4
; The bytes are spaced by BYTESPERROW because the target bitmap is stored as
; interleaved bitplanes.
; -----------------------------------------------------------------------------

_DrawRotoBodyAsm::
	movem.l d2-d7/a1-a6,-(sp)      ; save all registers used by this routine
	lea     -12(sp),sp             ; reserve 12 bytes of local stack storage

	; Load pointers needed by the hotloop.
	movea.l (a0),a1                ; a1 = Params->Texture
	movea.l RA_RowPtr(a0),a6       ; a6 = Params->RowPtr cursor

	; Load affine step increments.
	move.w  RA_DuDx(a0),d4         ; d4 = DuDx
	move.w  RA_DvDx(a0),d5         ; d5 = DvDx
	move.w  RA_DuDy(a0),2(sp)      ; local DuDy
	move.w  RA_DvDy(a0),4(sp)      ; local DvDy

	; Load the starting coordinates for the first logical row.
	move.w  RA_RowU(a0),6(sp)      ; local RowU
	move.w  RA_RowV(a0),8(sp)      ; local RowV

	; Split the contiguous PairExpand block into its three logical tables.
	movea.l RA_Expand(a0),a2       ; a2 = plane 0/1 word table base
	lea     2048(a2),a3            ; a3 = plane 2/3 word table base
	lea     4096(a2),a4            ; a4 = plane 4 byte table base

	; Process exactly 48 logical rows.
	move.w  #ROTO_ROWS-1,(sp)      ; outer loop countdown

; -----------------------------------------------------------------------------
; Outer loop: render one logical row.
; The C side already prepared one destination pointer per logical row.
; -----------------------------------------------------------------------------
.row_loop:
	tst.w   (sp)                    ; row counter negative yet?
	bmi.w   .done                   ; yes -> all rows finished

	; Load the start U/V for this logical row.
	move.w  6(sp),d0                ; d0 = current row start U
	move.w  8(sp),d1                ; d1 = current row start V

	; Fetch the destination pointer for this logical row.
	movea.l (a6)+,a5                ; a5 = destination plane-0 byte pointer

	; 12 iterations * 2 packed pairs = 24 packed pairs = 48 logical pixels.
	moveq   #ROTO_LOOP_COUNT-1,d6

; -----------------------------------------------------------------------------
; Inner loop: two packed pairs per iteration.
; One packed pair = 2 chunky texels -> 1 byte in each of 5 bitplanes.
; -----------------------------------------------------------------------------
.pair_loop2:
	; =====================================================================
	; Pair 1, texel 0 (c0)
	; ---------------------------------------------------------------------
	; Internal texture is 256 x 128.
	; The integer texture coordinates are:
	;   texY = (V >> 8) & 127
	;   texX = (U >> 8) & 255
	; Because each texture row is 256 bytes wide, the row base is simply:
	;   texY * 256 = (V & $7F00)
	; =====================================================================
	move.w  d1,d7                   ; d7 = V
	andi.w  #$7F00,d7               ; keep integer Y bits already aligned as texY*256

	move.w  d0,d3                   ; d3 = U
	lsr.w   #8,d3                   ; d3 = integer X = (U >> 8)
	add.w   d3,d7                   ; d7 = texY * 256 + texX

	move.b  (a1,d7.w),d2            ; d2 = first sampled texel (c0)
	ext.w   d2                      ; normalize byte to word cheaply

	add.w   d4,d0                   ; U += DuDx
	add.w   d5,d1                   ; V += DvDx

	; =====================================================================
	; Pair 1, texel 1 (c1)
	; =====================================================================
	move.w  d1,d7                   ; d7 = V for the second texel
	andi.w  #$7F00,d7               ; texY * 256

	move.w  d0,d3                   ; d3 = U
	lsr.w   #8,d3                   ; texX = (U >> 8)
	add.w   d3,d7                   ; full texture index

	move.b  (a1,d7.w),d7            ; d7 = second sampled texel (c1)
	ext.w   d7                      ; normalize byte to word
	lsl.w   #5,d7                   ; move c1 into bits 5..9
	or.w    d2,d7                   ; packed = c0 | (c1 << 5)

	add.w   d4,d0                   ; U += DuDx
	add.w   d5,d1                   ; V += DvDx

	; Plane 4 uses a byte table and can be written directly with packed.
	move.b  (a4,d7.w),(BYTESPERROW*4)(a5)

	; Plane 0/1 and plane 2/3 use WORD tables.
	; Scale packed by 2 because each entry is one word wide.
	add.w   d7,d7                   ; packed * 2
	move.w  (a2,d7.w),d2            ; d2 = [plane0 byte | plane1 byte]
	move.w  (a3,d7.w),d3            ; d3 = [plane2 byte | plane3 byte]

	; Write plane 0 and plane 1 from d2.
	move.b  d2,(a5)                 ; plane 0 byte
	lsr.w   #8,d2
	move.b  d2,BYTESPERROW(a5)      ; plane 1 byte

	; Write plane 2 and plane 3 from d3.
	move.b  d3,(BYTESPERROW*2)(a5)  ; plane 2 byte
	lsr.w   #8,d3
	move.b  d3,(BYTESPERROW*3)(a5)  ; plane 3 byte

	addq.l  #1,a5                   ; advance to the next packed pair byte

	; =====================================================================
	; Pair 2, texel 0 (c0)
	; Same logic as pair 1. Duplicating the code reduces loop overhead.
	; =====================================================================
	move.w  d1,d7                   ; d7 = V
	andi.w  #$7F00,d7               ; texY * 256

	move.w  d0,d3                   ; d3 = U
	lsr.w   #8,d3                   ; texX = (U >> 8)
	add.w   d3,d7                   ; full texture index

	move.b  (a1,d7.w),d2            ; d2 = first texel of pair 2
	ext.w   d2                      ; normalize to word

	add.w   d4,d0                   ; U += DuDx
	add.w   d5,d1                   ; V += DvDx

	; =====================================================================
	; Pair 2, texel 1 (c1)
	; =====================================================================
	move.w  d1,d7                   ; d7 = V
	andi.w  #$7F00,d7               ; texY * 256

	move.w  d0,d3                   ; d3 = U
	lsr.w   #8,d3                   ; texX = (U >> 8)
	add.w   d3,d7                   ; full texture index

	move.b  (a1,d7.w),d7            ; d7 = second texel of pair 2
	ext.w   d7                      ; normalize to word
	lsl.w   #5,d7                   ; c1 << 5
	or.w    d2,d7                   ; packed = c0 | (c1 << 5)

	add.w   d4,d0                   ; U += DuDx
	add.w   d5,d1                   ; V += DvDx

	; Plane 4 from the byte table.
	move.b  (a4,d7.w),(BYTESPERROW*4)(a5)

	; Planes 0/1 and 2/3 from the word tables.
	add.w   d7,d7                   ; packed * 2
	move.w  (a2,d7.w),d2            ; plane 0/1 word
	move.w  (a3,d7.w),d3            ; plane 2/3 word

	move.b  d2,(a5)                 ; plane 0 byte
	lsr.w   #8,d2
	move.b  d2,BYTESPERROW(a5)      ; plane 1 byte
	move.b  d3,(BYTESPERROW*2)(a5)  ; plane 2 byte
	lsr.w   #8,d3
	move.b  d3,(BYTESPERROW*3)(a5)  ; plane 3 byte

	addq.l  #1,a5                   ; next packed pair byte

	dbra    d6,.pair_loop2          ; continue until all 24 packed pairs are written

	; Advance the row start coordinates for the next logical row.
	move.w  2(sp),d7                ; d7 = DuDy
	add.w   d7,6(sp)                ; RowU += DuDy
	move.w  4(sp),d7                ; d7 = DvDy
	add.w   d7,8(sp)                ; RowV += DvDy

	subq.w  #1,(sp)                 ; next outer row
	bra.w   .row_loop               ; continue with the next logical row

.done:
	lea     12(sp),sp               ; release local stack storage
	movem.l (sp)+,d2-d7/a1-a6       ; restore saved registers
	rts                             ; return to C
