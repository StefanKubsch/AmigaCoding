; -----------------------------------------------------------------------------
; Sprite-assist hybrid rotozoomer drawing routine - rowless pair-split core
; Amiga 500 OCS / 68000 - vasm Motorola syntax
;
; Renders all three spans in one 48-row loop:
; - left  64 pixels -> playfield wings
; - center 64 pixels -> attached sprite DMA buffers directly
; - right 64 pixels -> playfield wings
;
; Main difference versus the previous working hybrid:
; - no per-row pointer table anymore
; - C passes only two running bases per buffer:
;     * compact playfield row 0 base
;     * sprite channel 0 data row 0 base
; - the hotloop derives all row destinations from fixed strides
;
; Lookup strategy:
; - PairSplit[pair].Lo / .Hi, 256 entries interleaved
; - Expand4Pix[256] as ULONG : [high-plane word | low-plane word]
; -----------------------------------------------------------------------------

	machine 68000

	include "lwmf/lwmf_hardware_regs.i"

ROTO_ROWS              equ 48
PF_PLANEBYTES          equ 24             ; 192 pixels / 8
PF_ROW_STRIDE          equ 96             ; 24 bytes * 4 planes
PF_RIGHT_START         equ 16             ; skip left wing (8 bytes) + center span (8 bytes)
SPR_CHANNEL_STRIDE     equ 776            ; bytes between adjacent sprite channels
SPR_ROW_STRIDE         equ 16             ; 4 visible sprite rows * 1 long per row
SPR_PAIR_NEXT_ADJ      equ 1536           ; (2*SPR_CHANNEL_STRIDE) - SPR_ROW_STRIDE

; -----------------------------------------------------------------------------
; struct RotoAsmParams
; -----------------------------------------------------------------------------
RA_Texture             equ 0
RA_PfBase              equ 4
RA_SprBase             equ 8
RA_Expand              equ 12
RA_RowU                equ 16
RA_RowV                equ 18
RA_DuDx                equ 20
RA_DvDx                equ 22
RA_DuDy                equ 24
RA_DvDy                equ 26

; -----------------------------------------------------------------------------
; PairExpand layout
; -----------------------------------------------------------------------------
PE_PairSplit           equ 0
PE_Expand4Pix          equ 1024

; -----------------------------------------------------------------------------
; Stack locals
; -----------------------------------------------------------------------------
LOC_RowCnt             equ 0
LOC_DuDy               equ 2
LOC_DvDy               equ 4
LOC_RowU               equ 6
LOC_RowV               equ 8
LOC_PfBase             equ 10
LOC_SprBase            equ 14
LOC_DuFrac             equ 18
LOC_DvFrac             equ 19
LOC_SIZE               equ 20

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

_DrawRotoHybridAsm::
	movem.l d2-d7/a1-a6,-(sp)
	lea     -LOC_SIZE(sp),sp

	movea.l RA_Texture(a0),a5
	move.l  RA_PfBase(a0),LOC_PfBase(sp)
	move.l  RA_SprBase(a0),LOC_SprBase(sp)

	moveq   #0,d4
	move.b  RA_DuDx(a0),d4
	move.b  RA_DuDx+1(a0),LOC_DuFrac(sp)

	moveq   #0,d5
	move.b  RA_DvDx(a0),d5
	move.b  RA_DvDx+1(a0),LOC_DvFrac(sp)

	move.w  RA_DuDy(a0),LOC_DuDy(sp)
	move.w  RA_DvDy(a0),LOC_DvDy(sp)

	move.w  RA_RowU(a0),LOC_RowU(sp)
	move.w  RA_RowV(a0),LOC_RowV(sp)

	movea.l RA_Expand(a0),a1
	movea.l a1,a0                   ; a0 = PairSplit base for whole routine
	movea.l a1,a6
	adda.l  #PE_Expand4Pix,a6       ; a6 = Expand4Pix base

	move.w  #ROTO_ROWS-1,LOC_RowCnt(sp)

.row_loop:
	tst.w   LOC_RowCnt(sp)
	bmi.w   .done

	movea.l LOC_PfBase(sp),a1
	lea     PF_PLANEBYTES(a1),a2
	lea     PF_PLANEBYTES(a2),a3
	lea     PF_PLANEBYTES(a3),a4

	moveq   #0,d0
	moveq   #0,d1
	moveq   #0,d2
	moveq   #0,d3

	move.b  LOC_RowU+1(sp),d0
	move.b  LOC_RowU(sp),d1
	move.b  LOC_RowV+1(sp),d2
	move.b  LOC_RowV(sp),d3

	; Left/Right block 1
	moveq   #0,d6
	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	lsl.w   #8,d6

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	moveq   #0,d7
	move.b  d6,d7
	lsr.w   #8,d6

	add.w   d6,d6
	add.w   d6,d6
	move.w  0(a0,d6.w),d6

	add.w   d7,d7
	add.w   d7,d7
	or.w    2(a0,d7.w),d6

	moveq   #0,d7
	move.b  d6,d7
	lsr.w   #8,d6

	add.w   d7,d7
	add.w   d7,d7
	move.l  (a6,d7.w),d7

	add.w   d6,d6
	add.w   d6,d6
	move.l  (a6,d6.w),d6
	move.w  d7,(a1)+
	swap    d7
	move.w  d7,(a2)+
	move.w  d6,(a3)+
	swap    d6
	move.w  d6,(a4)+

	; Left/Right block 2
	moveq   #0,d6
	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	lsl.w   #8,d6

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	moveq   #0,d7
	move.b  d6,d7
	lsr.w   #8,d6

	add.w   d6,d6
	add.w   d6,d6
	move.w  0(a0,d6.w),d6

	add.w   d7,d7
	add.w   d7,d7
	or.w    2(a0,d7.w),d6

	moveq   #0,d7
	move.b  d6,d7
	lsr.w   #8,d6

	add.w   d7,d7
	add.w   d7,d7
	move.l  (a6,d7.w),d7

	add.w   d6,d6
	add.w   d6,d6
	move.l  (a6,d6.w),d6
	move.w  d7,(a1)+
	swap    d7
	move.w  d7,(a2)+
	move.w  d6,(a3)+
	swap    d6
	move.w  d6,(a4)+

	; Left/Right block 3
	moveq   #0,d6
	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	lsl.w   #8,d6

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	moveq   #0,d7
	move.b  d6,d7
	lsr.w   #8,d6

	add.w   d6,d6
	add.w   d6,d6
	move.w  0(a0,d6.w),d6

	add.w   d7,d7
	add.w   d7,d7
	or.w    2(a0,d7.w),d6

	moveq   #0,d7
	move.b  d6,d7
	lsr.w   #8,d6

	add.w   d7,d7
	add.w   d7,d7
	move.l  (a6,d7.w),d7

	add.w   d6,d6
	add.w   d6,d6
	move.l  (a6,d6.w),d6
	move.w  d7,(a1)+
	swap    d7
	move.w  d7,(a2)+
	move.w  d6,(a3)+
	swap    d6
	move.w  d6,(a4)+

	; Left/Right block 4
	moveq   #0,d6
	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	lsl.w   #8,d6

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	moveq   #0,d7
	move.b  d6,d7
	lsr.w   #8,d6

	add.w   d6,d6
	add.w   d6,d6
	move.w  0(a0,d6.w),d6

	add.w   d7,d7
	add.w   d7,d7
	or.w    2(a0,d7.w),d6

	moveq   #0,d7
	move.b  d6,d7
	lsr.w   #8,d6

	add.w   d7,d7
	add.w   d7,d7
	move.l  (a6,d7.w),d7

	add.w   d6,d6
	add.w   d6,d6
	move.l  (a6,d6.w),d6
	move.w  d7,(a1)+
	swap    d7
	move.w  d7,(a2)+
	move.w  d6,(a3)+
	swap    d6
	move.w  d6,(a4)+

	movea.l LOC_SprBase(sp),a1
	lea     SPR_CHANNEL_STRIDE(a1),a3

	; Center block 1
	moveq   #0,d6
	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	lsl.w   #8,d6

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	moveq   #0,d7
	move.b  d6,d7
	lsr.w   #8,d6

	add.w   d6,d6
	add.w   d6,d6
	move.w  0(a0,d6.w),d6

	add.w   d7,d7
	add.w   d7,d7
	or.w    2(a0,d7.w),d6

	moveq   #0,d7
	move.b  d6,d7
	lsr.w   #8,d6

	add.w   d7,d7
	add.w   d7,d7
	move.l  (a6,d7.w),d7

	add.w   d6,d6
	add.w   d6,d6
	move.l  (a6,d6.w),d6
	swap    d7
	move.l  d7,(a1)+
	move.l  d7,(a1)+
	move.l  d7,(a1)+
	move.l  d7,(a1)+
	swap    d6
	move.l  d6,(a3)+
	move.l  d6,(a3)+
	move.l  d6,(a3)+
	move.l  d6,(a3)+
	lea     SPR_PAIR_NEXT_ADJ(a1),a1
	lea     SPR_PAIR_NEXT_ADJ(a3),a3

	; Center block 2
	moveq   #0,d6
	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	lsl.w   #8,d6

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	moveq   #0,d7
	move.b  d6,d7
	lsr.w   #8,d6

	add.w   d6,d6
	add.w   d6,d6
	move.w  0(a0,d6.w),d6

	add.w   d7,d7
	add.w   d7,d7
	or.w    2(a0,d7.w),d6

	moveq   #0,d7
	move.b  d6,d7
	lsr.w   #8,d6

	add.w   d7,d7
	add.w   d7,d7
	move.l  (a6,d7.w),d7

	add.w   d6,d6
	add.w   d6,d6
	move.l  (a6,d6.w),d6
	swap    d7
	move.l  d7,(a1)+
	move.l  d7,(a1)+
	move.l  d7,(a1)+
	move.l  d7,(a1)+
	swap    d6
	move.l  d6,(a3)+
	move.l  d6,(a3)+
	move.l  d6,(a3)+
	move.l  d6,(a3)+
	lea     SPR_PAIR_NEXT_ADJ(a1),a1
	lea     SPR_PAIR_NEXT_ADJ(a3),a3

	; Center block 3
	moveq   #0,d6
	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	lsl.w   #8,d6

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	moveq   #0,d7
	move.b  d6,d7
	lsr.w   #8,d6

	add.w   d6,d6
	add.w   d6,d6
	move.w  0(a0,d6.w),d6

	add.w   d7,d7
	add.w   d7,d7
	or.w    2(a0,d7.w),d6

	moveq   #0,d7
	move.b  d6,d7
	lsr.w   #8,d6

	add.w   d7,d7
	add.w   d7,d7
	move.l  (a6,d7.w),d7

	add.w   d6,d6
	add.w   d6,d6
	move.l  (a6,d6.w),d6
	swap    d7
	move.l  d7,(a1)+
	move.l  d7,(a1)+
	move.l  d7,(a1)+
	move.l  d7,(a1)+
	swap    d6
	move.l  d6,(a3)+
	move.l  d6,(a3)+
	move.l  d6,(a3)+
	move.l  d6,(a3)+
	lea     SPR_PAIR_NEXT_ADJ(a1),a1
	lea     SPR_PAIR_NEXT_ADJ(a3),a3

	; Center block 4
	moveq   #0,d6
	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	lsl.w   #8,d6

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	moveq   #0,d7
	move.b  d6,d7
	lsr.w   #8,d6

	add.w   d6,d6
	add.w   d6,d6
	move.w  0(a0,d6.w),d6

	add.w   d7,d7
	add.w   d7,d7
	or.w    2(a0,d7.w),d6

	moveq   #0,d7
	move.b  d6,d7
	lsr.w   #8,d6

	add.w   d7,d7
	add.w   d7,d7
	move.l  (a6,d7.w),d7

	add.w   d6,d6
	add.w   d6,d6
	move.l  (a6,d6.w),d6
	swap    d7
	move.l  d7,(a1)+
	move.l  d7,(a1)+
	move.l  d7,(a1)+
	move.l  d7,(a1)+
	swap    d6
	move.l  d6,(a3)+
	move.l  d6,(a3)+
	move.l  d6,(a3)+
	move.l  d6,(a3)+

	movea.l LOC_PfBase(sp),a1
	lea     PF_RIGHT_START(a1),a1
	lea     PF_PLANEBYTES(a1),a2
	lea     PF_PLANEBYTES(a2),a3
	lea     PF_PLANEBYTES(a3),a4

	; Left/Right block 1
	moveq   #0,d6
	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	lsl.w   #8,d6

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	moveq   #0,d7
	move.b  d6,d7
	lsr.w   #8,d6

	add.w   d6,d6
	add.w   d6,d6
	move.w  0(a0,d6.w),d6

	add.w   d7,d7
	add.w   d7,d7
	or.w    2(a0,d7.w),d6

	moveq   #0,d7
	move.b  d6,d7
	lsr.w   #8,d6

	add.w   d7,d7
	add.w   d7,d7
	move.l  (a6,d7.w),d7

	add.w   d6,d6
	add.w   d6,d6
	move.l  (a6,d6.w),d6
	move.w  d7,(a1)+
	swap    d7
	move.w  d7,(a2)+
	move.w  d6,(a3)+
	swap    d6
	move.w  d6,(a4)+

	; Left/Right block 2
	moveq   #0,d6
	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	lsl.w   #8,d6

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	moveq   #0,d7
	move.b  d6,d7
	lsr.w   #8,d6

	add.w   d6,d6
	add.w   d6,d6
	move.w  0(a0,d6.w),d6

	add.w   d7,d7
	add.w   d7,d7
	or.w    2(a0,d7.w),d6

	moveq   #0,d7
	move.b  d6,d7
	lsr.w   #8,d6

	add.w   d7,d7
	add.w   d7,d7
	move.l  (a6,d7.w),d7

	add.w   d6,d6
	add.w   d6,d6
	move.l  (a6,d6.w),d6
	move.w  d7,(a1)+
	swap    d7
	move.w  d7,(a2)+
	move.w  d6,(a3)+
	swap    d6
	move.w  d6,(a4)+

	; Left/Right block 3
	moveq   #0,d6
	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	lsl.w   #8,d6

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	moveq   #0,d7
	move.b  d6,d7
	lsr.w   #8,d6

	add.w   d6,d6
	add.w   d6,d6
	move.w  0(a0,d6.w),d6

	add.w   d7,d7
	add.w   d7,d7
	or.w    2(a0,d7.w),d6

	moveq   #0,d7
	move.b  d6,d7
	lsr.w   #8,d6

	add.w   d7,d7
	add.w   d7,d7
	move.l  (a6,d7.w),d7

	add.w   d6,d6
	add.w   d6,d6
	move.l  (a6,d6.w),d6
	move.w  d7,(a1)+
	swap    d7
	move.w  d7,(a2)+
	move.w  d6,(a3)+
	swap    d6
	move.w  d6,(a4)+

	; Left/Right block 4
	moveq   #0,d6
	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	lsl.w   #8,d6

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	moveq   #0,d7
	move.b  d6,d7
	lsr.w   #8,d6

	add.w   d6,d6
	add.w   d6,d6
	move.w  0(a0,d6.w),d6

	add.w   d7,d7
	add.w   d7,d7
	or.w    2(a0,d7.w),d6

	moveq   #0,d7
	move.b  d6,d7
	lsr.w   #8,d6

	add.w   d7,d7
	add.w   d7,d7
	move.l  (a6,d7.w),d7

	add.w   d6,d6
	add.w   d6,d6
	move.l  (a6,d6.w),d6
	move.w  d7,(a1)+
	swap    d7
	move.w  d7,(a2)+
	move.w  d6,(a3)+
	swap    d6
	move.w  d6,(a4)+

	movea.l LOC_PfBase(sp),a1
	lea     PF_ROW_STRIDE(a1),a1
	move.l  a1,LOC_PfBase(sp)

	movea.l LOC_SprBase(sp),a1
	lea     SPR_ROW_STRIDE(a1),a1
	move.l  a1,LOC_SprBase(sp)

	move.w  LOC_DuDy(sp),d7
	add.w   d7,LOC_RowU(sp)
	move.w  LOC_DvDy(sp),d7
	add.w   d7,LOC_RowV(sp)

	subq.w  #1,LOC_RowCnt(sp)
	bra.w   .row_loop

.done:
	lea     LOC_SIZE(sp),sp
	movem.l (sp)+,d2-d7/a1-a6
	rts
