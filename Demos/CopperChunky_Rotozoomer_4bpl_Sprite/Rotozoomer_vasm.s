; -----------------------------------------------------------------------------
; Sprite-assist hybrid rotozoomer drawing routine - rowless pair-split core
; Amiga 500 OCS / 68000 - vasm Motorola syntax
;
;
; (C) 2026 Stefan Kubsch / Deep4
; -----------------------------------------------------------------------------

	machine 68000                          ; Assemble for plain Motorola 68000.

	include "lwmf/lwmf_hardware_regs.i"   ; Import Amiga hardware register definitions.

ROTO_ROWS              equ 48             ; Number of logical roto rows.
PF_PLANEBYTES          equ 24             ; Bytes per playfield bitplane row (192 pixels / 8).
PF_ROW_STRIDE          equ 96             ; Bytes between two logical rows across 4 bitplanes.
PF_RIGHT_START         equ 16             ; Byte offset from PF row base to the right wing start.
SPR_CHANNEL_STRIDE     equ 776            ; Byte distance between neighbouring sprite DMA channels.
SPR_ROW_STRIDE         equ 16             ; Byte advance for one logical sprite row.
SPR_PAIR_NEXT_ADJ      equ 1536           ; Adjustment from one sprite pair write to the next pair.

; -----------------------------------------------------------------------------
; struct RotoAsmParams
; -----------------------------------------------------------------------------
RA_Texture             equ 0              ; Offset: texture sample base pointer.
RA_PfBase              equ 4              ; Offset: playfield row 0 base pointer.
RA_SprBase             equ 8              ; Offset: sprite data row 0 base pointer.
RA_Expand              equ 12             ; Offset: PairExpand table base pointer.
RA_RowU                equ 16             ; Offset: starting U coordinate for the current frame.
RA_RowV                equ 18             ; Offset: starting V coordinate for the current frame.
RA_DuDx                equ 20             ; Offset: U delta per pixel in X.
RA_DvDx                equ 22             ; Offset: V delta per pixel in X.
RA_DuDy                equ 24             ; Offset: U delta per logical row in Y.
RA_DvDy                equ 26             ; Offset: V delta per logical row in Y.

; -----------------------------------------------------------------------------
; PairExpand layout
; -----------------------------------------------------------------------------
PE_PairSplit           equ 0              ; PairSplit table starts at base + 0.
PE_Expand4Pix          equ 1024           ; Expand4Pix table starts at base + 1024 bytes.

; -----------------------------------------------------------------------------
; Stack locals
; -----------------------------------------------------------------------------
LOC_RowCnt             equ 0              ; Loop counter for logical rows.
LOC_DuDy               equ 2              ; Cached U delta per row.
LOC_DvDy               equ 4              ; Cached V delta per row.
LOC_RowU               equ 6              ; Current row start U.
LOC_RowV               equ 8              ; Current row start V.
LOC_PfBase             equ 10             ; Current playfield row base pointer.
LOC_SprBase            equ 14             ; Current sprite row base pointer.
LOC_DuFrac             equ 18             ; Fractional byte of DuDx.
LOC_DvFrac             equ 19             ; Fractional byte of DvDx.
LOC_SIZE               equ 20             ; Total size of the local stack frame.

; -----------------------------------------------------------------------------
; Register usage
; a0 = PairSplit base during hotloop
; a1 = plane0 pointer / current sprite-even pointer / scratch address
; a2 = plane1 pointer
; a3 = plane2 pointer / current sprite-odd pointer
; a4 = plane3 pointer
; a5 = texture sample base
; a6 = Expand4Pix base
;
; d0 = u_frac  (low byte used)
; d1 = u_int   (low byte used)
; d2 = v_frac  (low byte used)
; d3 = v_int   (low byte used)
; d4 = du_int  (low byte used)
; d5 = dv_int  (low byte used)
; d6 = pair/key/idx23 scratch
; d7 = pair/idx01/out01 scratch
; -----------------------------------------------------------------------------

; -----------------------------------------------------------------------------
; 4-pixel sampling/expansion core
; -----------------------------------------------------------------------------
	macro ADVANCE_UV                        ; Advance the fixed-point U/V coordinates by one sample.
	add.b   LOC_DuFrac(sp),d0               ; Add the fractional U step to the U fraction byte.
	addx.b  d4,d1                           ; Add integer U step plus carry from the fraction add.
	add.b   LOC_DvFrac(sp),d2               ; Add the fractional V step to the V fraction byte.
	addx.b  d5,d3                           ; Add integer V step plus carry from the fraction add.
	endm                                    ; End of ADVANCE_UV macro.

	macro SAMPLE_TEXEL_TO_D6                ; Sample one texel and place the 4-bit colour index into d6.
	move.w  d3,d7                           ; Copy current V integer to d7 for address construction.
	lsl.w   #8,d7                           ; Shift V into the high byte of a 16-bit texture offset.
	move.b  d1,d7                           ; Insert current U integer as the low byte of the offset.
	move.b  (a5,d7.w),d6                    ; Read the texel index from texture[V:U] into d6 low byte.
	ADVANCE_UV                              ; Step U/V to the next sample position.
	endm                                    ; End of SAMPLE_TEXEL_TO_D6.

	macro SAMPLE_TEXEL_TO_D7_LO             ; Sample one texel and OR it into the low nibble group of d6.
	move.w  d3,d7                           ; Copy current V integer to d7 for address construction.
	lsl.w   #8,d7                           ; Shift V into the high byte of the texture address.
	move.b  d1,d7                           ; Insert current U integer as the low byte of the texture address.
	move.b  (a5,d7.w),d7                    ; Read the texel index into d7 low byte.
	ext.w   d7                              ; Sign/zero-extend the sampled byte to a word-sized value.
	or.w    d7,d6                           ; Merge this texel into the partially built 16-bit packed pair word.
	ADVANCE_UV                              ; Step U/V to the next sample position.
	endm                                    ; End of SAMPLE_TEXEL_TO_D7_LO.

	macro SAMPLE_TEXEL_TO_D7_HI             ; Sample one texel and place it into the high nibble group in d6.
	move.w  d3,d7                           ; Copy current V integer to d7 for address construction.
	lsl.w   #8,d7                           ; Shift V into the high byte of the texture address.
	move.b  d1,d7                           ; Insert current U integer as the low byte of the texture address.
	move.b  (a5,d7.w),d7                    ; Read the texel index into d7 low byte.
	ext.w   d7                              ; Extend the sampled byte to word size.
	lsl.w   #4,d7                           ; Shift the colour index into the upper nibble position.
	or.w    d7,d6                           ; Merge this texel into the packed pair word in d6.
	ADVANCE_UV                              ; Step U/V to the next sample position.
	endm                                    ; End of SAMPLE_TEXEL_TO_D7_HI.

	macro BUILD_EXPANDED_BLOCK              ; Build one expanded 4-pixel block into d7/d6 plane words.
	moveq   #0,d6                           ; Clear d6 before assembling the packed pair key.
	SAMPLE_TEXEL_TO_D6                      ; Sample texel 0 into d6 low nibble area.
	SAMPLE_TEXEL_TO_D7_HI                   ; Sample texel 1 and place it into the matching high nibble area.

	lsl.w   #8,d6                           ; Shift the first texel pair into the upper byte for pair packing.

	SAMPLE_TEXEL_TO_D7_LO                   ; Sample texel 2 into the low part of the second pair.
	SAMPLE_TEXEL_TO_D7_HI                   ; Sample texel 3 into the high part of the second pair.

	moveq   #0,d7                           ; Clear d7 before extracting the low byte of the packed key.
	move.b  d6,d7                           ; Copy the low packed pair byte into d7.
	lsr.w   #8,d6                           ; Move the high packed pair byte down into d6 low byte.

	add.w   d6,d6                           ; Multiply pair index by 2...
	add.w   d6,d6                           ; ...and again, resulting in index * 4 for PairSplit entry size.
	move.w  0(a0,d6.w),d6                   ; Load PairSplit[pair_hi].Lo into d6.

	add.w   d7,d7                           ; Multiply second pair index by 2...
	add.w   d7,d7                           ; ...and again, resulting in index * 4.
	or.w    2(a0,d7.w),d6                   ; OR in PairSplit[pair_lo].Hi to form the 8-bit 2bpp pattern key.

	moveq   #0,d7                           ; Clear d7 before splitting the final 8-bit expansion key.
	move.b  d6,d7                           ; Copy low byte of key into d7.
	lsr.w   #8,d6                           ; Move high byte of key into d6 low byte.

	add.w   d7,d7                           ; Multiply low expansion index by 2...
	add.w   d7,d7                           ; ...and again, resulting in index * 4 for ULONG lookup.
	move.l  (a6,d7.w),d7                    ; Load expanded plane words for the first 2-bit pair group.

	add.w   d6,d6                           ; Multiply high expansion index by 2...
	add.w   d6,d6                           ; ...and again, resulting in index * 4.
	move.l  (a6,d6.w),d6                    ; Load expanded plane words for the second 2-bit pair group.
	endm                                    ; End of BUILD_EXPANDED_BLOCK.

; -----------------------------------------------------------------------------
; Output variants
; -----------------------------------------------------------------------------
	macro STORE_PF_BLOCK                    ; Store one 16-pixel expanded block into the 4 playfield bitplanes.
	move.w  d7,(a1)+                        ; Write plane 0 word and advance plane 0 pointer.
	swap    d7                              ; Swap upper and lower words to access plane 1 word.
	move.w  d7,(a2)+                        ; Write plane 1 word and advance plane 1 pointer.
	move.w  d6,(a3)+                        ; Write plane 2 word and advance plane 2 pointer.
	swap    d6                              ; Swap upper and lower words to access plane 3 word.
	move.w  d6,(a4)+                        ; Write plane 3 word and advance plane 3 pointer.
	endm                                    ; End of STORE_PF_BLOCK.

	macro STORE_SPR_BLOCK                   ; Store one 16-pixel expanded block into the sprite DMA layout.
	swap    d7                              ; Bring the even-sprite word pair into the low longword half.
	move.l  d7,(a1)+                        ; Write visible row 0 for the even sprite pair.
	move.l  d7,(a1)+                        ; Write visible row 1 for the even sprite pair.
	move.l  d7,(a1)+                        ; Write visible row 2 for the even sprite pair.
	move.l  d7,(a1)+                        ; Write visible row 3 for the even sprite pair.
	swap    d6                              ; Bring the odd-sprite word pair into the low longword half.
	move.l  d6,(a3)+                        ; Write visible row 0 for the odd sprite pair.
	move.l  d6,(a3)+                        ; Write visible row 1 for the odd sprite pair.
	move.l  d6,(a3)+                        ; Write visible row 2 for the odd sprite pair.
	move.l  d6,(a3)+                        ; Write visible row 3 for the odd sprite pair.
	lea     SPR_PAIR_NEXT_ADJ(a1),a1        ; Jump from this even sprite pair to the next even pair.
	lea     SPR_PAIR_NEXT_ADJ(a3),a3        ; Jump from this odd sprite pair to the next odd pair.
	endm                                    ; End of STORE_SPR_BLOCK.

	macro EMIT_PF_BLOCK                     ; Generate and store one playfield block.
	BUILD_EXPANDED_BLOCK                    ; Sample, pair-split and expand 4 texels.
	STORE_PF_BLOCK                          ; Write the resulting plane words to the playfield.
	endm                                    ; End of EMIT_PF_BLOCK.

	macro EMIT_SPR_BLOCK                    ; Generate and store one sprite block.
	BUILD_EXPANDED_BLOCK                    ; Sample, pair-split and expand 4 texels.
	STORE_SPR_BLOCK                         ; Write the resulting words to the sprite buffers.
	endm                                    ; End of EMIT_SPR_BLOCK.

_DrawRotoHybridAsm::                      ; Entry point called from C.
	movem.l d2-d7/a1-a6,-(sp)               ; Save all scratch/data registers used by the routine.
	lea     -LOC_SIZE(sp),sp                ; Reserve stack space for local variables.

	movea.l RA_Texture(a0),a5               ; Load texture sample base pointer into a5.
	move.l  RA_PfBase(a0),LOC_PfBase(sp)    ; Cache current playfield base pointer on the stack.
	move.l  RA_SprBase(a0),LOC_SprBase(sp)  ; Cache current sprite base pointer on the stack.

	moveq   #0,d4                           ; Clear d4 before loading the integer part of DuDx.
	move.b  RA_DuDx(a0),d4                  ; Load integer U step per pixel into d4 low byte.
	move.b  RA_DuDx+1(a0),LOC_DuFrac(sp)    ; Cache fractional U step byte on the stack.

	moveq   #0,d5                           ; Clear d5 before loading the integer part of DvDx.
	move.b  RA_DvDx(a0),d5                  ; Load integer V step per pixel into d5 low byte.
	move.b  RA_DvDx+1(a0),LOC_DvFrac(sp)    ; Cache fractional V step byte on the stack.

	move.w  RA_DuDy(a0),LOC_DuDy(sp)        ; Cache U step per logical row.
	move.w  RA_DvDy(a0),LOC_DvDy(sp)        ; Cache V step per logical row.

	move.w  RA_RowU(a0),LOC_RowU(sp)        ; Cache starting row U coordinate.
	move.w  RA_RowV(a0),LOC_RowV(sp)        ; Cache starting row V coordinate.

	movea.l RA_Expand(a0),a1                ; Load the combined PairExpand table base.
	movea.l a1,a0                           ; Keep PairSplit base in a0 for indexed lookups.
	movea.l a1,a6                           ; Copy PairExpand base to a6.
	adda.l  #PE_Expand4Pix,a6               ; Advance a6 to the Expand4Pix subtable.

	move.w  #ROTO_ROWS-1,LOC_RowCnt(sp)     ; Initialise row counter for 48 logical rows.

.row_loop:                                 ; Start of one logical display row.
	tst.w   LOC_RowCnt(sp)                  ; Test whether the row counter is still non-negative.
	bmi.w   .done                           ; Exit once all logical rows have been processed.

	movea.l LOC_PfBase(sp),a1               ; Load current playfield row base into a1.
	lea     PF_PLANEBYTES(a1),a2            ; Derive plane 1 row pointer from plane 0 pointer.
	lea     PF_PLANEBYTES(a2),a3            ; Derive plane 2 row pointer from plane 1 pointer.
	lea     PF_PLANEBYTES(a3),a4            ; Derive plane 3 row pointer from plane 2 pointer.

	moveq   #0,d0                           ; Clear current U fraction register.
	moveq   #0,d1                           ; Clear current U integer register.
	moveq   #0,d2                           ; Clear current V fraction register.
	moveq   #0,d3                           ; Clear current V integer register.

	move.b  LOC_RowU+1(sp),d0               ; Load fractional byte of row start U into d0.
	move.b  LOC_RowU(sp),d1                 ; Load integer byte of row start U into d1.
	move.b  LOC_RowV+1(sp),d2               ; Load fractional byte of row start V into d2.
	move.b  LOC_RowV(sp),d3                 ; Load integer byte of row start V into d3.

	; Left wing: 4 x 16 pixels to playfield
	REPT 4                                  ; Emit four consecutive 16-pixel playfield blocks.
	EMIT_PF_BLOCK                           ; Build one block and write it to the left wing.
	ENDR                                    ; End of left-wing repetition.

	movea.l LOC_SprBase(sp),a1              ; Load current sprite row base into even-sprite pointer.
	lea     SPR_CHANNEL_STRIDE(a1),a3       ; Derive odd-sprite pointer from even-sprite pointer.

	; Center span: 4 x 16 pixels to attached sprite DMA buffers
	REPT 4                                  ; Emit four consecutive 16-pixel sprite blocks.
	EMIT_SPR_BLOCK                          ; Build one block and write it to the centre sprite span.
	ENDR                                    ; End of centre-span repetition.

	movea.l LOC_PfBase(sp),a1               ; Reload current playfield row base.
	lea     PF_RIGHT_START(a1),a1           ; Advance to the byte offset where the right wing begins.
	lea     PF_PLANEBYTES(a1),a2            ; Derive right-wing plane 1 pointer.
	lea     PF_PLANEBYTES(a2),a3            ; Derive right-wing plane 2 pointer.
	lea     PF_PLANEBYTES(a3),a4            ; Derive right-wing plane 3 pointer.

	; Right wing: 4 x 16 pixels to playfield
	REPT 4                                  ; Emit four consecutive 16-pixel playfield blocks.
	EMIT_PF_BLOCK                           ; Build one block and write it to the right wing.
	ENDR                                    ; End of right-wing repetition.

	movea.l LOC_PfBase(sp),a1               ; Reload current playfield row base for row advance.
	lea     PF_ROW_STRIDE(a1),a1            ; Advance playfield base to the next logical row.
	move.l  a1,LOC_PfBase(sp)               ; Store updated playfield row base back to the stack.

	movea.l LOC_SprBase(sp),a1              ; Reload current sprite row base for row advance.
	lea     SPR_ROW_STRIDE(a1),a1           ; Advance sprite base to the next logical row.
	move.l  a1,LOC_SprBase(sp)              ; Store updated sprite row base back to the stack.

	move.w  LOC_DuDy(sp),d7                 ; Load U-per-row delta into d7.
	add.w   d7,LOC_RowU(sp)                 ; Advance row start U to the next logical row.
	move.w  LOC_DvDy(sp),d7                 ; Load V-per-row delta into d7.
	add.w   d7,LOC_RowV(sp)                 ; Advance row start V to the next logical row.

	subq.w  #1,LOC_RowCnt(sp)               ; Decrement remaining row counter.
	bra.w   .row_loop                       ; Process the next logical row.

.done:                                     ; All rows are complete.
	lea     LOC_SIZE(sp),sp                 ; Release the local stack frame.
	movem.l (sp)+,d2-d7/a1-a6               ; Restore saved registers.
	rts                                     ; Return to the C caller.
