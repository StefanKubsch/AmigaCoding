; Blitter line-mode functions for the Sine Scroller
; Amiga 500 OCS / 68000 — vasm Motorola syntax
;
; (C) 2026 by Stefan Kubsch
;

	machine 68000

	include "lwmf/lwmf_hardware_regs.i"

; ---------------------------------------------------------------------------
; Blitter line-mode constants
; LINE_DX = 15 (height-1), LINE_DY = 0 (width-1), octant 1 (upward)
; ---------------------------------------------------------------------------
BLTAPTL_VAL  equ  4*0-2*15                      ; Bresenham initial error: 4*DY-2*DX = -30
BLTCON1_VAL  equ  $F045                         ; BSH=15, SIGN=1, AUL=1, LINE=1
BLTCON0_BASE equ  $0B4A                         ; USEA|USEB|USEC|USED, LF=$4A (D=AB|AC)
BLTSIZE_VAL  equ  (16<<6)|2                     ; 16 rows, 2 words wide
BLTAMOD_VAL  equ  4*0-4*15                      ; 4*(DY-DX) = -60
BLTBMOD_VAL  equ  4*0                           ; 4*DY = 0
BLTMOD_VAL   equ  BYTESPERROW*NUMBEROFBITPLANES ; interleaved stride = 120
BLTADAT_VAL  equ  $8000                         ; line-mode start bit

; ---------------------------------------------------------------------------
; void InitScrollerBlitter(void)
;
; Waits for the blitter, then writes the five registers that remain constant
; for the entire lifetime of the scroller (called once from Init_SineScroller).
; ---------------------------------------------------------------------------

_InitScrollerBlitter::
	move.l	a5,-(sp)
	lea		CUSTOMREGS,a5
	bsr		_lwmf_WaitBlitter
	move.w	#$FFFF,(BLTAFWM-CUSTOMREGS,a5)        ; first-word mask: all bits
	move.w	#$FFFF,(BLTALWM-CUSTOMREGS,a5)        ; last-word mask:  all bits
	move.w	#BLTADAT_VAL,(BLTADAT-CUSTOMREGS,a5)  ; line-mode start bit
	move.w	#BLTAMOD_VAL,(BLTAMOD-CUSTOMREGS,a5)  ; A modulo: 4*(DY-DX)
	move.w	#BLTBMOD_VAL,(BLTBMOD-CUSTOMREGS,a5)  ; B modulo: 4*DY
	move.l	(sp)+,a5
	rts

; ---------------------------------------------------------------------------
; void DrawScrollerBlit(
;   __reg("a0") const ULONG *dataPtr,     FontData[FirstVisibleColumn]
;   __reg("a2") const ULONG *DataEnd,     one past last column
;   __reg("a3") const UWORD *offsetTab,   ScrollBottomWordOffset[320]
;   __reg("a4") const UBYTE *dstPlane,    ScreenBitmap->Planes[0]
;   __reg("d0") WORD         scrollX,
;   __reg("d1") WORD         rightVisX
; )
;
; FontData entry layout (ULONG): hi-word = ColumnBits, lo-word = ColumnDst
; One ULONG read per iteration replaces two separate WORD reads.
;
; Register map:
;   a0 = dataPtr  (auto-incremented via (a0)+, ULONG step)
;   a2 = DataEnd
;   a3 = offsetTab (ScrollBottomWordOffset, UWORD[320])
;   a4 = dstPlane
;   a5 = CUSTOMREGS ($DFF000)
;   d0 = scrollX    (constant)
;   d1 = rightVisX  (constant)
;   d2 = FontData entry: lo-word = ColumnDst; after swap: lo-word = ColumnBits
;   d3 = BLTCON0 value    (scratch per iteration)
;   d4 = dst chip-RAM address as ULONG (scratch per iteration)
;   d5 = dstX*2           (scratch per iteration)
; ---------------------------------------------------------------------------

_DrawScrollerBlit::
	movem.l	d2-d5/a2-a5,-(sp)
	lea		CUSTOMREGS,a5

	; Enable Blitter Nasty FIRST so the in-progress clear blit gets full bus priority
	; and finishes faster, reducing the time we spend in wait_init.
	move.w	#$8400,(DMACON-CUSTOMREGS,a5)

	; Wait for any previous blit (e.g. screen-clear) to finish before taking the blitter.
	; Without this, writing BLTCMOD/BLTDMOD below would corrupt an in-progress blit on A1200.
.wait_init:
	btst.b	#DMAB_BLITTER,(DMACONR-CUSTOMREGS,a5)
	bne.s	.wait_init

	; Write per-frame-constant registers once.
	move.w	#BLTCON1_VAL,(BLTCON1-CUSTOMREGS,a5)
	move.w	#BLTMOD_VAL,(BLTCMOD-CUSTOMREGS,a5)
	move.w	#BLTMOD_VAL,(BLTDMOD-CUSTOMREGS,a5)

	; BLTAPTL: for a purely vertical line DY=0, so the Bresenham error term
	; update per step is 2*DY=0 — the blitter never modifies BLTAPTL.
	move.w	#BLTAPTL_VAL,(BLTAPTL-CUSTOMREGS,a5)

.blit_loop:
	; bounds check: dstPtr >= DstEnd?
	cmpa.l	a2,a0
	bhs.s	.blit_done

	; load FontData entry: lo-word = ColumnDst, hi-word = ColumnBits
	move.l	(a0)+,d2

	; right-edge clip
	cmp.w	d1,d2
	bge.s	.blit_done

	; dstX = scrollX + dstTextX
	; scrollX is always even (decrements by 2/frame), so dstX >= 0 is guaranteed
	; by the C-side skip-loop (ColumnDst >= -scrollX). No left-edge clip needed.
	move.w	d0,d5                   ; d5 = scrollX
	add.w	d2,d5                   ; d5 = dstX

	; dstX*2 up front: used for both the BLTCON0 lookup and the offsetTab index
	add.w	d5,d5                   ; d5 = dstX*2

	; BLTCON0 via lookup: index = (dstX*2) & 0x1E
	; Combining *2 with the mask here saves one instruction vs. masking then doubling.
	move.w	d5,d3
	and.w	#$1E,d3                 ; d3 = (dstX & 0xF) * 2 — UWORD table offset in one step
	move.w	BLTCON0Tab(pc,d3.w),d3  ; d3 = pre-built BLTCON0 value

	; dst = (ULONG)dstPlane + (ULONG)offsetTab[dstX]
	; d5 = dstX*2 already, used directly as byte index
	moveq	#0,d4
	move.w	(a3,d5.w),d4           ; d4 = offsetTab[dstX] (zero-extended)
	add.l	a4,d4                  ; d4 = chip-RAM address of bottom-row word

	; extract ColumnBits from hi-word before the blitter wait.
	swap	d2                     ; d2.w = ColumnBits (was hi-word)

	; IMPORTANT: wait before touching any per-blit register.
.wait_blit:
	btst.b	#DMAB_BLITTER,(DMACONR-CUSTOMREGS,a5)
	bne.s	.wait_blit

	; Set last-word mask explicitly for every blit.
	cmp.w	#608,d5
	blt.s	.full_lwm
	clr.w	(BLTALWM-CUSTOMREGS,a5)
	bra.s	.lwm_ready
.full_lwm:
	move.w	#$FFFF,(BLTALWM-CUSTOMREGS,a5)
.lwm_ready:

	; write registers, start blit (BLTSIZE must be last)
	move.w	d3,(BLTCON0-CUSTOMREGS,a5)            ; shift + channel select + LF
	move.l	d4,(BLTCPTH-CUSTOMREGS,a5)            ; BLTCPTH+L (32-bit write)
	move.l	d4,(BLTDPTH-CUSTOMREGS,a5)            ; BLTDPTH+L (32-bit write)
	move.w	d2,(BLTBDAT-CUSTOMREGS,a5)            ; font column pattern (ColumnBits after swap)
	move.w	#BLTSIZE_VAL,(BLTSIZE-CUSTOMREGS,a5)  ; trigger blit

	bra.s	.blit_loop

.blit_done:
	; Wait for the last blit to finish before returning or any later cleanup/display work.
.wait_last:
	btst.b	#DMAB_BLITTER,(DMACONR-CUSTOMREGS,a5)
	bne.s	.wait_last

	; Disable Blitter Nasty only after the last blit has completed.
	move.w	#$0400,(DMACON-CUSTOMREGS,a5)

	movem.l	(sp)+,d2-d5/a2-a5
	rts

; BLTCON0 lookup table: index = dstX & 0xF, value = (index << 12) | BLTCON0_BASE
BLTCON0Tab:
	dc.w	$0B4A,$1B4A,$2B4A,$3B4A,$4B4A,$5B4A,$6B4A,$7B4A
	dc.w	$8B4A,$9B4A,$AB4A,$BB4A,$CB4A,$DB4A,$EB4A,$FB4A

; ---------------------------------------------------------------------------
; void UpdateScrollerRainbow(
;   __reg("a0") UWORD      **colorPtrTab,   ScrollRainbowColorPtr[0]
;   __reg("a1") const UWORD *rainbowTab,    RainbowTab[256] — precomputed RGB4, indexed by idx
;   __reg("d0") UWORD        phase,         RainbowPhase (UBYTE, zero-extended)
;   __reg("d1") UWORD        totalLines     SCROLLER_LINES
; )
;
; RainbowTab[i] = full RGB4 color for idx i (phase-independent, computed once in Init).
; Per-line idx = (i*3 + phase) & 0xFF, which maps to byte offset idx*2 in the UWORD table.
;
; Writes two consecutive UWORD slots per line in the Copper list:
;   *(p+0) = color (COLOR01)
;   *(p+4) = color (COLOR03)   (+4 bytes = skip the 0x186 register word)
;
; Register map:
;   a0 = colorPtrTab  (auto-advanced via move.l (a0)+,a2)
;   a1 = RainbowTab   (UWORD[256], constant)
;   a2 = current Copper UWORD* (loaded each iteration)
;   d0 = idx.b — byte index into RainbowTab (addq.b #3 wraps mod 256; bits 8-15 stay 0)
;   d1 = loop counter (dbra)
;   d3 = color word
;   d6 = idx*2 — byte offset into UWORD table (scratch per iteration)
; ---------------------------------------------------------------------------

_UpdateScrollerRainbow::
	movem.l	d3/d6/a2,-(sp)

	; Zero-extend phase once: addq.b only modifies bits 0-7, bits 8-15 stay 0.
	and.w	#$FF,d0
	subq.w	#1,d1                   ; pre-decrement for dbra

.rainbow_loop:
	move.w	d0,d6
	add.w	d6,d6                   ; d6 = idx * 2 (byte offset into UWORD table)
	move.w	(a1,d6.w),d3            ; d3 = RainbowTab[idx] — full RGB4

	move.l	(a0)+,a2                ; a2 = colorPtrTab[i]
	move.w	d3,(a2)
	move.w	d3,(4,a2)               ; +4 bytes = +2 UWORD slots (skip 0x186 register word)

	addq.b	#3,d0                   ; idx += 3 (bits 8-15 stay 0)
	dbra	d1,.rainbow_loop

	movem.l	(sp)+,d3/d6/a2
	rts
