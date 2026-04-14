; -----------------------------------------------------------------------------
; Rotozoomer drawing routine
; Amiga 500 OCS / 68000 - vasm Motorola syntax
;
; 128k variant with split sampler:
; - prepared plane pointers per logical row
; - move.w writes with postincrement
; - 256x256 vertically duplicated texture with biased sample base
; - Pair2Idx[65536] as UWORD : key = pair2 | (pair1 << 8)
; - Expand4Pix[256] as ULONG : [high-plane word | low-plane word]
; - U/V are tracked as split integer/fraction bytes
; - hotloop kept at 3 groups * 4 blocks = 12 blocks = 48 logical pixels
; -----------------------------------------------------------------------------

	machine 68000

	include "lwmf/lwmf_hardware_regs.i"

ROTO_ROWS             equ 48
ROTO_GROUP_COUNT      equ 3              ; 3 iterations * 4 blocks * 4 pixels = 48 pixels

; -----------------------------------------------------------------------------
; struct RotoRowPlanes
; -----------------------------------------------------------------------------
RRP_P0                equ 0
RRP_P1                equ 4
RRP_P2                equ 8
RRP_P3                equ 12
RRP_SIZE              equ 16

; -----------------------------------------------------------------------------
; struct RotoAsmParams
; Must match C exactly.
; -----------------------------------------------------------------------------
RA_Texture            equ 0
RA_RowPtr             equ 4
RA_Expand             equ 8
RA_RowU               equ 12
RA_RowV               equ 14
RA_DuDx               equ 16
RA_DvDx               equ 18
RA_DuDy               equ 20
RA_DvDy               equ 22

; -----------------------------------------------------------------------------
; PairExpand layout
; -----------------------------------------------------------------------------
PE_Pair2Idx           equ 0
PE_Expand4Pix         equ 131072         ; 65536 * sizeof(UWORD)

; -----------------------------------------------------------------------------
; Stack locals
; -----------------------------------------------------------------------------
LOC_RowCnt            equ 0              ; word
LOC_DuDy              equ 2              ; word
LOC_DvDy              equ 4              ; word
LOC_RowU              equ 6              ; word
LOC_RowV              equ 8              ; word
LOC_RowPtr            equ 10             ; long
LOC_MapBase           equ 14             ; long
LOC_GroupCnt          equ 18             ; word
LOC_DuFrac            equ 20             ; byte
LOC_DvFrac            equ 21             ; byte
LOC_SIZE              equ 22

; -----------------------------------------------------------------------------
; Register usage
;
; a0 = Pair2Idx base during hotloop / row cursor before that
; a1 = plane 0 destination pointer
; a2 = plane 1 destination pointer
; a3 = plane 2 destination pointer
; a4 = plane 3 destination pointer
; a5 = texture sample base (middle of 256x256 signed window)
; a6 = Expand4Pix base
;
; d0 = u_frac  (low byte used)
; d1 = u_int   (low byte used, 0..255)
; d2 = v_frac  (low byte used)
; d3 = v_int   (low byte used, 0..255)
; d4 = du_int  (low byte used)
; d5 = dv_int  (low byte used)
; d6 = pair/key/idx01/out01 scratch
; d7 = address/texel/idx23/out23 scratch
; -----------------------------------------------------------------------------

_DrawRotoBodyAsm::
	movem.l d2-d7/a1-a6,-(sp)
	lea     -LOC_SIZE(sp),sp

	; Persistent pointers / increments.
	movea.l RA_Texture(a0),a5

	movea.l RA_Expand(a0),a1
	move.l  a1,LOC_MapBase(sp)
	movea.l a1,a6
	adda.l  #PE_Expand4Pix,a6

	movea.l RA_RowPtr(a0),a1
	move.l  a1,LOC_RowPtr(sp)

	; DuDx / DvDx split into integer byte in regs and fraction byte in locals.
	moveq   #0,d4
	move.b  RA_DuDx(a0),d4          ; high byte = integer part
	move.b  RA_DuDx+1(a0),LOC_DuFrac(sp)

	moveq   #0,d5
	move.b  RA_DvDx(a0),d5
	move.b  RA_DvDx+1(a0),LOC_DvFrac(sp)

	; Row-to-row deltas stay as full 8.8 words.
	move.w  RA_DuDy(a0),LOC_DuDy(sp)
	move.w  RA_DvDy(a0),LOC_DvDy(sp)

	move.w  RA_RowU(a0),LOC_RowU(sp)
	move.w  RA_RowV(a0),LOC_RowV(sp)

	move.w  #ROTO_ROWS-1,LOC_RowCnt(sp)

.row_loop:
	tst.w   LOC_RowCnt(sp)
	bmi.w   .done

	; Restore row cursor.
	movea.l LOC_RowPtr(sp),a0

	; Load prepared plane pointers for this logical row.
	movem.l (a0),a1-a4

	; Advance row cursor once and store it away.
	lea     RRP_SIZE(a0),a0
	move.l  a0,LOC_RowPtr(sp)

	; Restore Pair2Idx base for the hotloop.
	movea.l LOC_MapBase(sp),a0

	; Split current row start coordinates:
	;   word = [int][frac]
	moveq   #0,d0
	moveq   #0,d1
	moveq   #0,d2
	moveq   #0,d3

	move.b  LOC_RowU+1(sp),d0       ; u_frac
	move.b  LOC_RowU(sp),d1         ; u_int
	move.b  LOC_RowV+1(sp),d2       ; v_frac
	move.b  LOC_RowV(sp),d3         ; v_int

	move.w  #ROTO_GROUP_COUNT-1,LOC_GroupCnt(sp)

.group_loop:

	; =====================================================================
	; Block 1: Pair 1 + Pair 2 -> 4 pixels
	; Key format for Pair2Idx:
	;   key = pair2 | (pair1 << 8)
	; =====================================================================

	; Pair 1, texel 0
	moveq   #0,d6
	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d6
	ext.w   d6
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	; Pair 1, texel 1
	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6                  ; d6 = pair1 packed
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	; move pair1 into key high byte, clear low byte
	lsl.w   #8,d6

	; Pair 2, texel 0
	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	or.w    d7,d6                  ; low nibble of pair2
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	; Pair 2, texel 1
	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d7
	ext.w   d7
	lsl.w   #4,d7
	or.w    d7,d6                  ; d6 = key = pair2 | (pair1 << 8)
	add.b   LOC_DuFrac(sp),d0
	addx.b  d4,d1
	add.b   LOC_DvFrac(sp),d2
	addx.b  d5,d3

	; Pair2Idx lookup
	add.l   d6,d6
	move.w  0(a0,d6.l),d7          ; d7 = [idx23 | idx01]

	; idx01 -> d6
	moveq   #0,d6
	move.b  d7,d6

	; idx23 -> d7
	lsr.w   #8,d7

	; Expand idx01 -> [plane1 | plane0]
	add.w   d6,d6
	add.w   d6,d6
	move.l  (a6,d6.w),d6

	; Expand idx23 -> [plane3 | plane2]
	add.w   d7,d7
	add.w   d7,d7
	move.l  (a6,d7.w),d7

	; Write plane words
	move.w  d6,(a1)+               ; plane 0
	swap    d6
	move.w  d6,(a2)+               ; plane 1

	move.w  d7,(a3)+               ; plane 2
	swap    d7
	move.w  d7,(a4)+               ; plane 3

	; =====================================================================
	; Block 2: Pair 3 + Pair 4 -> 4 pixels
	; =====================================================================

	moveq   #0,d6
	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d6
	ext.w   d6
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

	add.l   d6,d6
	move.w  0(a0,d6.l),d7

	moveq   #0,d6
	move.b  d7,d6
	lsr.w   #8,d7

	add.w   d6,d6
	add.w   d6,d6
	move.l  (a6,d6.w),d6

	add.w   d7,d7
	add.w   d7,d7
	move.l  (a6,d7.w),d7

	move.w  d6,(a1)+
	swap    d6
	move.w  d6,(a2)+

	move.w  d7,(a3)+
	swap    d7
	move.w  d7,(a4)+

	; =====================================================================
	; Block 3: Pair 5 + Pair 6 -> 4 pixels
	; =====================================================================

	moveq   #0,d6
	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d6
	ext.w   d6
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

	add.l   d6,d6
	move.w  0(a0,d6.l),d7

	moveq   #0,d6
	move.b  d7,d6
	lsr.w   #8,d7

	add.w   d6,d6
	add.w   d6,d6
	move.l  (a6,d6.w),d6

	add.w   d7,d7
	add.w   d7,d7
	move.l  (a6,d7.w),d7

	move.w  d6,(a1)+
	swap    d6
	move.w  d6,(a2)+

	move.w  d7,(a3)+
	swap    d7
	move.w  d7,(a4)+

	; =====================================================================
	; Block 4: Pair 7 + Pair 8 -> 4 pixels
	; =====================================================================

	moveq   #0,d6
	move.w  d3,d7
	lsl.w   #8,d7
	move.b  d1,d7
	move.b  (a5,d7.w),d6
	ext.w   d6
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

	add.l   d6,d6
	move.w  0(a0,d6.l),d7

	moveq   #0,d6
	move.b  d7,d6
	lsr.w   #8,d7

	add.w   d6,d6
	add.w   d6,d6
	move.l  (a6,d6.w),d6

	add.w   d7,d7
	add.w   d7,d7
	move.l  (a6,d7.w),d7

	move.w  d6,(a1)+
	swap    d6
	move.w  d6,(a2)+

	move.w  d7,(a3)+
	swap    d7
	move.w  d7,(a4)+

	subq.w  #1,LOC_GroupCnt(sp)
	bpl.w   .group_loop

	; Advance row start coordinates for the next logical row.
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