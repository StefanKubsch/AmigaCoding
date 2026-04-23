; -----------------------------------------------------------------------------
; HAM / 7-bitplane rotozoomer drawing routine
; Amiga 500 OCS / 68000 - vasm Motorola syntax
;
; C prebuilds a compact 16-byte frame table for 256 frames. This routine only:
;   - fetches FrameTab[FramePhase]
;   - fetches DestBase[Buffer]
;   - samples the 256x128 RGB444 texture
;   - packs one 50x50 logical HAM image into 4 DMA bitplanes
;   - advances FramePhase with 8-bit wraparound
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
; The visible image uses 50 texels per row, but the fetched line is 52 texels
; wide: one black guard texel on the left and one on the right.
;
; (C) 2026 by Stefan Kubsch
; -----------------------------------------------------------------------------

	machine 68000

	include "lwmf/lwmf_hardware_regs.i"

	xref    _FrameTab
	xref    _FramePhase
	xref    _DestBase
	xref    _TextureRGB444
	xref    _HamPackLUT

	xdef    _Draw_RotoZoomerAsm
	xdef    Draw_RotoZoomerAsm

FRAME_ROWU          equ     0
FRAME_ROWV          equ     2
FRAME_DUDX          equ     4
FRAME_DVDX          equ     6
FRAME_ROWSTEPU      equ     8
FRAME_ROWSTEPV      equ     10

ROTO_ROWS           equ     50
ROTO_FETCH_BYTES    equ     26
ROW_ADVANCE         equ     BYTESPERROW*NUMBEROFBITPLANES-ROTO_FETCH_BYTES

; Stack locals after SUBA.W #16,SP
ROWSTEPU            equ     0
ROWSTEPV            equ     2
ROWCOUNT            equ     4
ROWU                equ     6
ROWV                equ     8
DUDX                equ     10
DVDX                equ     12
MIDCOUNT            equ     14

PUSH_BLACK  macro
	lsl.w   #4,d0
	lsl.w   #4,d1
	lsl.w   #4,d2
	lsl.w   #4,d3
	endm

SAMPLE_PACK macro
	move.w  d7,d4                   ; V
	lsr.w   #8,d4
	andi.w  #$007F,d4              ; texture height = 128
	lsl.w   #8,d4                  ; v * 256

	move.w  d6,d5                  ; U
	lsr.w   #8,d5
	andi.w  #$00FF,d5
	add.w   d5,d4
	add.w   d4,d4                  ; UWORD texture offset
	move.w  0(a5,d4.w),d4          ; RGB444 texel (0..4095)
	add.w   d4,d4                  ; *2
	add.w   d4,d4                  ; *4 for ULONG LUT
	move.l  0(a6,d4.w),d4          ; bytes: p0,p1,p2,p3 (68000-safe extraction)

	lsl.w   #4,d0
	move.l  d4,d5
	swap    d5
	lsr.w   #8,d5                  ; p0 -> low byte
	or.w    d5,d0

	lsl.w   #4,d1
	move.l  d4,d5
	swap    d5
	andi.w  #$00FF,d5              ; p1 -> low byte
	or.w    d5,d1

	lsl.w   #4,d2
	move.w  d4,d5
	lsr.w   #8,d5                  ; p2 -> low byte
	or.w    d5,d2

	lsl.w   #4,d3
	move.w  d4,d5
	andi.w  #$00FF,d5              ; p3 -> low byte
	or.w    d5,d3

	add.w   DUDX(sp),d6
	add.w   DVDX(sp),d7
	endm

	section .text,code

Draw_RotoZoomerAsm:
_Draw_RotoZoomerAsm:
	movem.l d2-d7/a2-a6,-(sp)
	suba.w  #16,sp

	lea     _FramePhase(pc),a0
	moveq   #0,d1
	move.b  (a0),d1
	addq.b  #1,(a0)

	lsl.w   #4,d1                  ; phase * sizeof(RotoFrame)
	lea     _FrameTab(pc),a0
	adda.w  d1,a0

	move.w  FRAME_ROWSTEPU(a0),d4
	move.w  d4,ROWSTEPU(sp)
	move.w  FRAME_ROWSTEPV(a0),d4
	move.w  d4,ROWSTEPV(sp)
	move.w  FRAME_ROWU(a0),d4
	move.w  d4,ROWU(sp)
	move.w  FRAME_ROWV(a0),d4
	move.w  d4,ROWV(sp)
	move.w  FRAME_DUDX(a0),d4
	move.w  d4,DUDX(sp)
	move.w  FRAME_DVDX(a0),d4
	move.w  d4,DVDX(sp)
	move.w  #ROTO_ROWS-1,ROWCOUNT(sp)

	lea     _DestBase(pc),a0
	andi.w  #1,d0
	lsl.w   #2,d0
	movea.l 0(a0,d0.w),a1          ; plane 0
	movea.l a1,a2
	adda.w  #BYTESPERROW,a2        ; plane 1
	movea.l a2,a3
	adda.w  #BYTESPERROW,a3        ; plane 2
	movea.l a3,a4
	adda.w  #BYTESPERROW,a4        ; plane 3

	movea.l _TextureRGB444(pc),a5
	lea     _HamPackLUT(pc),a6

.rowloop
	move.w  ROWU(sp),d6            ; current U
	move.w  ROWV(sp),d7            ; current V

	; -------------------------------------------------------------
	; First word: left guard texel (black) + first 3 visible texels
	; -------------------------------------------------------------
	moveq   #0,d0
	moveq   #0,d1
	moveq   #0,d2
	moveq   #0,d3
	PUSH_BLACK
	SAMPLE_PACK
	SAMPLE_PACK
	SAMPLE_PACK

	move.w  d0,(a1)+
	move.w  d1,(a2)+
	move.w  d2,(a3)+
	move.w  d3,(a4)+

	; -------------------------------------------------------------
	; Middle 11 words: 44 visible texels
	; -------------------------------------------------------------
	move.w  #11,MIDCOUNT(sp)
.midloop
	moveq   #0,d0
	moveq   #0,d1
	moveq   #0,d2
	moveq   #0,d3
	SAMPLE_PACK
	SAMPLE_PACK
	SAMPLE_PACK
	SAMPLE_PACK

	move.w  d0,(a1)+
	move.w  d1,(a2)+
	move.w  d2,(a3)+
	move.w  d3,(a4)+

	subq.w  #1,MIDCOUNT(sp)
	bne.w   .midloop

	; -------------------------------------------------------------
	; Last word: last 3 visible texels + right guard texel (black)
	; -------------------------------------------------------------
	moveq   #0,d0
	moveq   #0,d1
	moveq   #0,d2
	moveq   #0,d3
	SAMPLE_PACK
	SAMPLE_PACK
	SAMPLE_PACK
	PUSH_BLACK

	move.w  d0,(a1)+
	move.w  d1,(a2)+
	move.w  d2,(a3)+
	move.w  d3,(a4)+

	adda.w  #ROW_ADVANCE,a1
	adda.w  #ROW_ADVANCE,a2
	adda.w  #ROW_ADVANCE,a3
	adda.w  #ROW_ADVANCE,a4

	move.w  ROWU(sp),d4
	add.w   ROWSTEPU(sp),d4
	move.w  d4,ROWU(sp)
	move.w  ROWV(sp),d4
	add.w   ROWSTEPV(sp),d4
	move.w  d4,ROWV(sp)

	subq.w  #1,ROWCOUNT(sp)
	bpl     .rowloop

	adda.w  #16,sp
	movem.l (sp)+,d2-d7/a2-a6
	rts
