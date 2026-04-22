; -----------------------------------------------------------------------------
; Rotozoomer drawing routine
; Amiga 500 OCS / 68000 - vasm Motorola syntax
;
; The whole animation repeats after 256 frames. C therefore prebuilds a compact
; 16-byte frame table entry for every frame, and this routine only has to:
;   - fetch FrameTab[FramePhase]
;   - fetch DestBase[Buffer]
;   - render the 48x48 logical chunky image
;   - advance FramePhase with 8-bit wraparound
;
; Frame layout (must match the C struct exactly):
;   WORD RowU
;   WORD RowV
;   WORD DuDx
;   WORD DvDx
;   WORD RowStepU
;   WORD RowStepV
;   WORD Pad0
;   WORD Pad1
;
; (C) 2026 by Stefan Kubsch
; -----------------------------------------------------------------------------

	machine 68000                          ; Assemble for a plain Motorola 68000.

	include "lwmf/lwmf_hardware_regs.i"    ; Import hardware-related constants used by the project.

	xref _TextureChunky                    ; External pointer/base for the preconverted 256x128 texture.
	xref _PairExpand                       ; External lookup table that expands two chunky texels into bitplane bytes.
	xref _FrameTab                         ; External pointer/base to the 256-entry prebuilt frame table.
	xref _DestBase                         ; External table with destination base pointers for the two screen buffers.
	xref _FramePhase                       ; External 8-bit frame counter used to step through FrameTab.

ROTO_ROWS        equ 48                    ; Number of logical rows rendered by the CPU.
ROTO_LOOP_COUNT  equ 12                    ; 12 loop iterations * 2 macro calls = 24 pairs = 48 logical pixels.
ROTO_ROW_ADVANCE equ (BYTESPERROW*4)-24    ; Advance from end of one logical row to start of next row in interleaved output.

RF_RowU          equ  0                    ; Offset of RowU inside one frame table entry.
RF_RowV          equ  2                    ; Offset of RowV inside one frame table entry.
RF_DuDx          equ  4                    ; Offset of DuDx inside one frame table entry.
RF_DvDx          equ  6                    ; Offset of DvDx inside one frame table entry.
RF_RowStepU      equ  8                    ; Offset of RowStepU inside one frame table entry.
RF_RowStepV      equ 10                    ; Offset of RowStepV inside one frame table entry.
RF_SIZE          equ 16                    ; Total size of one frame table entry in bytes.

LOC_RowCount     equ 0                     ; One local word on the stack used as outer row counter.

PROCESS_PAIR macro                         ; Render two logical texels and emit one byte per plane.
	move.w  d1,d7                          ; Copy current V to D7 so we can derive the texture row index.
	andi.w  #$7F00,d7                      ; Keep only bits 8..14 of V: texture Y modulo 128, already shifted by 8.
	move.w  d0,d3                          ; Copy current U to D3 so we can derive the texture column index.
	lsr.w   #8,d3                          ; Convert U from 8.8 fixed point to integer X (0..255 because texture is duplicated horizontally).
	add.w   d3,d7                          ; Combine row base and column to get final texture offset.
	move.b  (a1,d7.w),d2                   ; Read first 4-bit texel value from the chunky texture.
	andi.w  #$00FF,d2                      ; Clear the upper byte so D2 safely holds an unsigned 8-bit value.
	add.w   d4,d0                          ; Advance U by DuDx for the second sample.
	add.w   d5,d1                          ; Advance V by DvDx for the second sample.

	move.w  d1,d7                          ; Copy updated V to D7 for the second texel fetch.
	andi.w  #$7F00,d7                      ; Keep only the wrapped texture Y part for the second sample.
	move.w  d0,d3                          ; Copy updated U to D3 for the second texel fetch.
	lsr.w   #8,d3                          ; Convert updated U from 8.8 fixed point to integer X.
	add.w   d3,d7                          ; Combine Y and X into the second texture offset.
	move.b  (a1,d7.w),d7                   ; Read second 4-bit texel value.
	andi.w  #$00FF,d7                      ; Clear the upper byte so D7 is again a clean 8-bit value.
	lsl.w   #4,d7                          ; Shift the second texel into the high nibble position.
	or.w    d2,d7                          ; Pack second texel (high nibble) and first texel (low nibble) into one 8-bit pair key.
	add.w   d4,d0                          ; Advance U again so D0/D1 are ready for the next pair.
	add.w   d5,d1                          ; Advance V again so D0/D1 are ready for the next pair.

	add.w   d7,d7                          ; Multiply pair key by 2 because the lookup tables store words.
	move.w  (a2,d7.w),d2                   ; Fetch preexpanded plane 0/1 bytes for this texel pair.
	move.w  (a3,d7.w),d3                   ; Fetch preexpanded plane 2/3 bytes for this texel pair.
	move.b  d2,(a5)                        ; Write plane 0 byte for the current output position.
	lsr.w   #8,d2                          ; Move plane 1 byte into the low byte of D2.
	move.b  d2,BYTESPERROW(a5)             ; Write plane 1 byte one row-stride below plane 0 in interleaved memory.
	move.b  d3,(BYTESPERROW*2)(a5)         ; Write plane 2 byte two row-strides below plane 0.
	lsr.w   #8,d3                          ; Move plane 3 byte into the low byte of D3.
	move.b  d3,(BYTESPERROW*3)(a5)         ; Write plane 3 byte three row-strides below plane 0.
	addq.l  #1,a5                          ; Advance destination pointer to the next byte column within the current logical row.
	endm                                   ; End of the two-texel rendering macro.

_Draw_RotoZoomerAsm::                      ; Public entry point: render one frame into the selected destination buffer.
	movem.l d2-d7/a1-a5,-(sp)              ; Save all scratch/data registers and address registers used by this routine.
	lea     -2(sp),sp                      ; Reserve one local word on the stack for the outer row counter.

	moveq   #0,d7                          ; Clear D7 so the upcoming byte load yields a clean unsigned frame index.
	move.b  _FramePhase,d7                 ; Load the current frame phase (0..255).
	addq.b  #1,_FramePhase                 ; Advance frame phase with implicit 8-bit wraparound for the next call.
	lsl.w   #4,d7                          ; Multiply frame index by 16 because each frame entry is 16 bytes.

	movea.l _FrameTab,a0                   ; Load the base pointer to the frame table into A0.
	adda.w  d7,a0                          ; Advance A0 to the current frame entry.

	movea.l _TextureChunky,a1              ; Load the base pointer to the chunky texture.
	lea     _PairExpand,a2                 ; A2 points to the first half of PairExpand (plane 0/1 words).
	lea     512(a2),a3                     ; A3 points to the second half of PairExpand (plane 2/3 words), 256 words = 512 bytes later.

	moveq   #0,d2                          ; Clear D2 so the buffer index becomes a clean unsigned value.
	move.b  d0,d2                          ; Copy the incoming buffer number from D0 into D2.
	lsl.w   #2,d2                          ; Multiply by 4 because DestBase contains longword pointers.
	lea     _DestBase,a5                   ; Load the address of the destination pointer table.
	movea.l 0(a5,d2.w),a5                  ; Load DestBase[buffer] into A5 as the current output pointer.

	movem.w RF_RowU(a0),d0-d1/d4-d5        ; Load RowU, RowV, DuDx and DvDx from the current frame entry.
	move.w  #ROTO_ROWS-1,LOC_RowCount(sp)  ; Initialize the outer loop counter for 48 logical rows.

.row_loop:                                 ; Start of one logical output row.
	moveq   #ROTO_LOOP_COUNT-1,d6          ; Initialize inner loop counter: 12 iterations per row.

.pair_loop:                                ; Inner loop that emits 4 logical pixels per iteration.
	PROCESS_PAIR                           ; Render the first texel pair of this iteration.
	PROCESS_PAIR                           ; Render the second texel pair of this iteration.
	dbra    d6,.pair_loop                  ; Repeat until all 24 pairs (= 48 texels) of the row are done.

	add.w   RF_RowStepU(a0),d0             ; Move U from the end of the current row to the start of the next row.
	add.w   RF_RowStepV(a0),d1             ; Move V from the end of the current row to the start of the next row.
	adda.w  #ROTO_ROW_ADVANCE,a5           ; Advance destination pointer to the next logical row start.
	subq.w  #1,LOC_RowCount(sp)            ; Decrement outer row counter stored on the stack.
	bpl.w   .row_loop                      ; Continue as long as the counter is still non-negative.

	lea     2(sp),sp                       ; Release the local stack word used for the outer row counter.
	movem.l (sp)+,d2-d7/a1-a5              ; Restore all registers saved on entry.
	rts                                    ; Return to the caller.
