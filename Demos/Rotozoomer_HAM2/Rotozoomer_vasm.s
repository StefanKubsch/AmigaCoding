;*************************************************************************
;* 4x4 HAM7 BPLDAT Quirk Rotozoomer ASM Renderer                         *
;*                                                                       *
;* 52x52 hybrid row cache renderer. Rows 26-48 are cached at half-rate.  *
;* Rows 49-51 are displayed directly from a slow-row cache via Copper.    *
;* Runtime draws rows 0-1 and splits rows 2-25.                           *
;* BPL5DAT/BPL6DAT control words are handled by the Copperlist in C.     *
;*************************************************************************

        machine 68000

	include	"lwmf/lwmf_hardware_regs.i"

	include	"Rotozoomer_shared.i"

; void InitHamBlitterCopyModeAsm(void)
; Initializes the fixed A-to-D blitter mode and full source masks.

_InitHamBlitterCopyModeAsm::
.bwi:   btst.b  #DMAB_BLITTER,DMACONR     ; wait before changing blitter copy state
        bne.s   .bwi                      ; loop while blitter is busy
        move.l  #(BLTCON0_COPY_A_TO_D<<16),BLTCON0 ; set A-to-D copy mode and clear BLTCON1
        move.l  #$FFFFFFFF,BLTAFWM        ; use all bits in first and last source words
        rts                               ; return to C

; void WaitHamLiveDoneAndSwitchCopperAsm(a0=CopperList)

_WaitHamLiveDoneAndSwitchCopperAsm::
        lea     CUSTOMREGS,a1             ; use custom base for beam and copper access
        move.l  a0,(COP1LCH-CUSTOMREGS,a1) ; prepare copper list for the next frame early
        btst.b  #0,(VPOSR+1-CUSTOMREGS,a1) ; test PAL line bit 8
        bne.s   .done                     ; rendering is safe in lower border/vblank
        cmp.b   #HAM_CORE_DONE_LOW,(VPOSR+2-CUSTOMREGS,a1) ; check if core rows are already off-screen
        bhs.s   .done                     ; rendering is safe when core rows are past
.wait_live:
        cmp.b   #HAM_CORE_DONE_LOW,(VPOSR+2-CUSTOMREGS,a1) ; wait for first line below core rows
        blo.s   .wait_live                ; stay while the beam still reads core rows
.done:
        rts                               ; return to C

; void UpdateHamCachedPointersAsm(a0=CopperList, a1=HalfPointers, a2=SlowRows)
_UpdateHamCachedPointersAsm::
	move.l	a0,d0					; keep copper-list base for the slow pointer slot
	lea	HAM_COPPER_HALFRATE_BPLPTR_BYTES(a0),a0	; get half-rate pointer value slot
	move.w	(a1),(a0)				; write plane 0 high word from prebuilt table
	move.w	2(a1),4(a0)				; write plane 0 low word from prebuilt table
	move.w	4(a1),8(a0)				; write plane 1 high word from prebuilt table
	move.w	6(a1),12(a0)				; write plane 1 low word from prebuilt table
	move.w	8(a1),16(a0)				; write plane 2 high word from prebuilt table
	move.w	10(a1),20(a0)			; write plane 2 low word from prebuilt table
	move.w	12(a1),24(a0)			; write plane 3 high word from prebuilt table
	move.w	14(a1),28(a0)			; write plane 3 low word from prebuilt table
	lea	CUSTOMREGS,a0				; use custom base for the slow-cache copper guard
	btst.b	#0,(VPOSR+1-CUSTOMREGS,a0)	; test PAL line bit 8 before touching slow pointer slots
	bne.s	.wait_slow_low			; after line 255: only low-byte safety remains
	cmp.b	#HAM_CORE_DONE_LOW,(VPOSR+2-CUSTOMREGS,a0)	; detect wrap into the next frame
	blo.s	.slow_cache_safe		; updating is safe after the old frame wrapped away
.wait_slow_high:
	btst.b	#0,(VPOSR+1-CUSTOMREGS,a0)	; wait for the row-49 slow area after line 255
	beq.s	.wait_slow_high		; stay while the beam is before the wrap line
.wait_slow_low:
	cmp.b	#HAM_SLOW_DONE_LOW,(VPOSR+2-CUSTOMREGS,a0)	; wait for first line below slow rows
	blo.s	.wait_slow_low		; stay while the beam still reads slow rows
.slow_cache_safe:
	movea.l	d0,a0					; restore copper-list base for slow cache pointers
	lea	HAM_COPPER_SLOW_BPLPTR_BYTES(a0),a0	; get slow-cache pointer value slot
	move.l	a2,d0					; d0 = slow plane 0 pointer
	move.l	d0,d1					; copy pointer for high-word extraction
	swap	d1					; put high word into low word
	move.w	d1,(a0)				; write plane 0 high word
	move.w	d0,4(a0)				; write plane 0 low word
	add.l	#HAM_SLOW_ROW_CACHE_PLANE_BYTES,d0	; advance to slow plane 1
	move.l	d0,d1					; copy pointer for high-word extraction
	swap	d1					; put high word into low word
	move.w	d1,8(a0)				; write plane 1 high word
	move.w	d0,12(a0)				; write plane 1 low word
	add.l	#HAM_SLOW_ROW_CACHE_PLANE_BYTES,d0	; advance to slow plane 2
	move.l	d0,d1					; copy pointer for high-word extraction
	swap	d1					; put high word into low word
	move.w	d1,16(a0)				; write plane 2 high word
	move.w	d0,20(a0)				; write plane 2 low word
	add.l	#HAM_SLOW_ROW_CACHE_PLANE_BYTES,d0	; advance to slow plane 3
	move.l	d0,d1					; copy pointer for high-word extraction
	swap	d1					; put high word into low word
	move.w	d1,24(a0)				; write plane 3 high word
	move.w	d0,28(a0)				; write plane 3 low word
	rts						; return without any slow-row blit

; void CopyHamTemporalUpperRowsAsm(a0=TargetDynamicFrame, a1=SourceDynamicFrame)
; Uses blitter for A->D copy of upper temporal half (rows 2-13), all 4 planes.
; Returns immediately after firing the tail chunk; the next blitter user waits as needed.
_CopyHamTemporalUpperRowsAsm::
        lea     HAM_TEMPORAL_UPPER_DEST_OFFSET(a0),a0 ; target will start at upper temporal rows
        lea     HAM_TEMPORAL_UPPER_DEST_OFFSET(a1),a1 ; source will start at upper temporal rows
        move.l  a0,d0                    ; d0 = destination chunk pointer
        move.l  a1,d1                    ; d1 = source chunk pointer
        lea     CUSTOMREGS,a0             ; use custom base without a callee-saved register
        move.w  #BLTPRI_SET,(DMACON-CUSTOMREGS,a0) ; give blitter priority while this routine waits
.bwu0:  btst.b  #DMAB_BLITTER,(DMACONR-CUSTOMREGS,a0) ; wait for any previous blit to finish
        bne.s   .bwu0                     ; loop while busy
        move.l  #BLIT_TEMPORAL_WIDE_MOD_LONG,(BLTAMOD-CUSTOMREGS,a0) ; set source and dest wide modulos
        move.l  d1,(BLTAPTH-CUSTOMREGS,a0) ; chunk 0: write source pointer
        move.l  d0,(BLTDPTH-CUSTOMREGS,a0) ; chunk 0: write destination pointer
        move.w  #BLIT_TEMPORAL_WIDE_SIZE,(BLTSIZE-CUSTOMREGS,a0) ; fire chunk 0 for all planes
        add.l   #BLIT_TEMPORAL_WIDE_BYTES,d0 ; advance dest to chunk 1
        add.l   #BLIT_TEMPORAL_WIDE_BYTES,d1 ; advance source to chunk 1
.bwu1:  btst.b  #DMAB_BLITTER,(DMACONR-CUSTOMREGS,a0) ; wait for chunk 0 blit done
        bne.s   .bwu1                     ; loop while busy
        move.l  d1,(BLTAPTH-CUSTOMREGS,a0) ; chunk 1: write source pointer
        move.l  d0,(BLTDPTH-CUSTOMREGS,a0) ; chunk 1: write destination pointer
        move.w  #BLIT_TEMPORAL_WIDE_SIZE,(BLTSIZE-CUSTOMREGS,a0) ; fire chunk 1 for all planes
        add.l   #BLIT_TEMPORAL_WIDE_BYTES,d0 ; advance dest to tail chunk
        add.l   #BLIT_TEMPORAL_WIDE_BYTES,d1 ; advance source to tail chunk
.bwu2:  btst.b  #DMAB_BLITTER,(DMACONR-CUSTOMREGS,a0) ; wait for chunk 1 blit done
        bne.s   .bwu2                     ; loop while busy
        move.l  #BLIT_TEMPORAL_TAIL_MOD_LONG,(BLTAMOD-CUSTOMREGS,a0) ; set source and dest tail modulos
        move.l  d1,(BLTAPTH-CUSTOMREGS,a0) ; tail chunk: write source pointer
        move.l  d0,(BLTDPTH-CUSTOMREGS,a0) ; tail chunk: write destination pointer
        move.w  #BLTPRI_CLR,(DMACON-CUSTOMREGS,a0) ; let final chunk overlap with CPU work
        move.w  #BLIT_TEMPORAL_TAIL_SIZE,(BLTSIZE-CUSTOMREGS,a0) ; fire tail chunk for all planes
        rts                              ; tail blit runs in parallel with CPU

; void CopyHamTemporalLowerRowsAsm(a0=TargetDynamicFrame, a1=SourceDynamicFrame)
; Uses blitter for A->D copy of lower temporal half (rows 14-25), all 4 planes.
; Returns immediately after firing the tail chunk; the next blitter user waits as needed.
_CopyHamTemporalLowerRowsAsm::
        lea     HAM_TEMPORAL_LOWER_DEST_OFFSET(a0),a0 ; target will start at lower temporal rows
        lea     HAM_TEMPORAL_LOWER_DEST_OFFSET(a1),a1 ; source will start at lower temporal rows
        move.l  a0,d0                    ; d0 = destination chunk pointer
        move.l  a1,d1                    ; d1 = source chunk pointer
        lea     CUSTOMREGS,a0             ; use custom base without a callee-saved register
        move.w  #BLTPRI_SET,(DMACON-CUSTOMREGS,a0) ; give blitter priority while this routine waits
.bwl0:  btst.b  #DMAB_BLITTER,(DMACONR-CUSTOMREGS,a0) ; wait for any previous blit to finish
        bne.s   .bwl0                     ; loop while busy
        move.l  #BLIT_TEMPORAL_WIDE_MOD_LONG,(BLTAMOD-CUSTOMREGS,a0) ; set source and dest wide modulos
        move.l  d1,(BLTAPTH-CUSTOMREGS,a0) ; chunk 0: write source pointer
        move.l  d0,(BLTDPTH-CUSTOMREGS,a0) ; chunk 0: write destination pointer
        move.w  #BLIT_TEMPORAL_WIDE_SIZE,(BLTSIZE-CUSTOMREGS,a0) ; fire chunk 0 for all planes
        add.l   #BLIT_TEMPORAL_WIDE_BYTES,d0 ; advance dest to chunk 1
        add.l   #BLIT_TEMPORAL_WIDE_BYTES,d1 ; advance source to chunk 1
.bwl1:  btst.b  #DMAB_BLITTER,(DMACONR-CUSTOMREGS,a0) ; wait for chunk 0 blit done
        bne.s   .bwl1                     ; loop while busy
        move.l  d1,(BLTAPTH-CUSTOMREGS,a0) ; chunk 1: write source pointer
        move.l  d0,(BLTDPTH-CUSTOMREGS,a0) ; chunk 1: write destination pointer
        move.w  #BLIT_TEMPORAL_WIDE_SIZE,(BLTSIZE-CUSTOMREGS,a0) ; fire chunk 1 for all planes
        add.l   #BLIT_TEMPORAL_WIDE_BYTES,d0 ; advance dest to tail chunk
        add.l   #BLIT_TEMPORAL_WIDE_BYTES,d1 ; advance source to tail chunk
.bwl2:  btst.b  #DMAB_BLITTER,(DMACONR-CUSTOMREGS,a0) ; wait for chunk 1 blit done
        bne.s   .bwl2                     ; loop while busy
        move.l  #BLIT_TEMPORAL_TAIL_MOD_LONG,(BLTAMOD-CUSTOMREGS,a0) ; set source and dest tail modulos
        move.l  d1,(BLTAPTH-CUSTOMREGS,a0) ; tail chunk: write source pointer
        move.l  d0,(BLTDPTH-CUSTOMREGS,a0) ; tail chunk: write destination pointer
        move.w  #BLTPRI_CLR,(DMACON-CUSTOMREGS,a0) ; let final chunk overlap with CPU work
        move.w  #BLIT_TEMPORAL_TAIL_SIZE,(BLTSIZE-CUSTOMREGS,a0) ; fire tail chunk for all planes
        rts                              ; tail blit runs in parallel with CPU

; void RenderHamTemporalUpperRowsAsm(a0=Base, a1=TextureCellsMid, a2=UOffsetTableMid,
;                                      a3=PairTables, d0=RowU, d1=RowV,
;                                      d2=DuDx, d3=DvDx, d6=RowUDelta, d7=RowVDelta)

_RenderHamTemporalUpperRowsAsm::
        btst.b  #0,VPOSR+1                ; test PAL line bit 8 before touching temporal rows
        bne.s   .temporal_render_safe     ; rendering is safe in lower border/vblank
        cmp.b   #HAM_TEMPORAL_UPPER_DONE_LOW,VPOSR+2 ; check if this temporal half is already off-screen
        bhs.s   .temporal_render_safe     ; render immediately when this temporal half is safe
.wait_temporal_render:
        cmp.b   #HAM_TEMPORAL_UPPER_DONE_LOW,VPOSR+2 ; wait for first line below this temporal half
        blo.s   .wait_temporal_render     ; stay while the beam still reads those rows
.temporal_render_safe:
        movem.l d4-d7/a3-a6,-(sp)        ; save clobbered C registers only
        movea.l a3,a6                    ; a6 = interleaved pair table base
        lea     RenderHamRowsCoreRowUDelta+2(pc),a5 ; get shared row U delta immediate
        move.w  d6,(a5)                  ; patch row U delta from frame params
        lea     RenderHamRowsCoreRowVDelta+2(pc),a5 ; get shared row V delta immediate
        move.w  d7,(a5)                  ; patch row V delta from frame params
        moveq   #HAM_TEMPORAL_HALF_ROWS-1,d5 ; d5 = temporal rows remaining after current row
        lea     HAM_TEMPORAL_UPPER_DEST_OFFSET(a0),a3 ; a3 = temporal plane 0 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a3),a4 ; a4 = temporal plane 1 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a4),a5 ; a5 = temporal plane 2 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a5),a0 ; a0 = temporal plane 3 write pointer
        bra.w   RenderHamRowsCore         ; render rows without per-row subroutine calls

; void RenderHamTemporalLowerRowsAsm(a0=Base, a1=TextureCellsMid, a2=UOffsetTableMid,
;                                      a3=PairTables, d0=RowU, d1=RowV,
;                                      d2=DuDx, d3=DvDx, d6=RowUDelta, d7=RowVDelta)

_RenderHamTemporalLowerRowsAsm::
        btst.b  #0,VPOSR+1                ; test PAL line bit 8 before touching temporal rows
        bne.s   .temporal_render_safe     ; rendering is safe in lower border/vblank
        cmp.b   #HAM_TEMPORAL_DONE_LOW,VPOSR+2 ; check if this temporal half is already off-screen
        bhs.s   .temporal_render_safe     ; render immediately when this temporal half is safe
.wait_temporal_render:
        cmp.b   #HAM_TEMPORAL_DONE_LOW,VPOSR+2 ; wait for first line below this temporal half
        blo.s   .wait_temporal_render     ; stay while the beam still reads those rows
.temporal_render_safe:
        movem.l d4-d7/a3-a6,-(sp)        ; save clobbered C registers only
        movea.l a3,a6                    ; a6 = interleaved pair table base
        lea     RenderHamRowsCoreRowUDelta+2(pc),a5 ; get shared row U delta immediate
        move.w  d6,(a5)                  ; patch row U delta from frame params
        lea     RenderHamRowsCoreRowVDelta+2(pc),a5 ; get shared row V delta immediate
        move.w  d7,(a5)                  ; patch row V delta from frame params
        moveq   #HAM_TEMPORAL_HALF_ROWS-1,d5 ; d5 = temporal rows remaining after current row
        lea     HAM_TEMPORAL_LOWER_DEST_OFFSET(a0),a3 ; a3 = temporal plane 0 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a3),a4 ; a4 = temporal plane 1 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a4),a5 ; a5 = temporal plane 2 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a5),a0 ; a0 = temporal plane 3 write pointer
        bra.w   RenderHamRowsCore         ; render rows without per-row subroutine calls

; void RenderHamLiveRowsAsm(a0=Base, a1=TextureCellsMid, a2=UOffsetTableMid,
;                             a3=PairTables, d0=RowU, d1=RowV,
;                             d2=DuDx, d3=DvDx, d6=RowUDelta, d7=RowVDelta)

_RenderHamLiveRowsAsm::
        movem.l d4-d7/a3-a6,-(sp)        ; save clobbered C registers only
        movea.l a3,a6                    ; a6 = interleaved pair table base
        lea     RenderHamRowsCoreRowUDelta+2(pc),a5 ; get shared row U delta immediate
        move.w  d6,(a5)                  ; patch row U delta from frame params
        lea     RenderHamRowsCoreRowVDelta+2(pc),a5 ; get shared row V delta immediate
        move.w  d7,(a5)                  ; patch row V delta from frame params
        moveq   #HAM_LIVE_ROWS-1,d5      ; d5 = live rows remaining after current row
        movea.l a0,a3                    ; a3 = live plane 0 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a3),a4 ; a4 = live plane 1 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a4),a5 ; a5 = live plane 2 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a5),a0 ; a0 = live plane 3 write pointer
        bra.w   RenderHamRowsCore         ; render rows through the shared inline core

; void RenderHamHalfRowsAsm(a0=Base, a1=TextureCellsMid, a2=UOffsetTableMid,
;                             a3=PairTables, d0=RowU, d1=RowV,
;                             d2=DuDx, d3=DvDx, d6=RowUDelta, d7=RowVDelta)

_RenderHamHalfRowsAsm::
        movem.l d4-d7/a3-a6,-(sp)        ; save clobbered C registers only
        movea.l a3,a6                    ; a6 = interleaved pair table base
        lea     RenderHamRowsCoreRowUDelta+2(pc),a5 ; get shared row U delta immediate
        move.w  d6,(a5)                  ; patch row U delta from frame params
        lea     RenderHamRowsCoreRowVDelta+2(pc),a5 ; get shared row V delta immediate
        move.w  d7,(a5)                  ; patch row V delta from frame params
        moveq   #HAM_HALFRATE_ROWS-1,d5  ; d5 = half-rate rows remaining after current row
        movea.l a0,a3                    ; a3 = half-rate plane 0 write pointer
        lea     HAM_HALFRATE_PLANE_BYTES(a3),a4 ; a4 = half-rate plane 1 write pointer
        lea     HAM_HALFRATE_PLANE_BYTES(a4),a5 ; a5 = half-rate plane 2 write pointer
        lea     HAM_HALFRATE_PLANE_BYTES(a5),a0 ; a0 = half-rate plane 3 write pointer
        bra.w   RenderHamRowsCore         ; render rows through the shared inline core

; void RenderHamSlowRowsAsm(a0=Base, a1=TextureCellsMid, a2=UOffsetTableMid,
;                             a3=PairTables, d0=RowU, d1=RowV,
;                             d2=DuDx, d3=DvDx, d6=RowUDelta, d7=RowVDelta)

_RenderHamSlowRowsAsm::
        movem.l d4-d7/a3-a6,-(sp)        ; save clobbered C registers only
        movea.l a3,a6                    ; a6 = interleaved pair table base
        lea     RenderHamRowsCoreRowUDelta+2(pc),a5 ; get shared row U delta immediate
        move.w  d6,(a5)                  ; patch row U delta from frame params
        lea     RenderHamRowsCoreRowVDelta+2(pc),a5 ; get shared row V delta immediate
        move.w  d7,(a5)                  ; patch row V delta from frame params
        moveq   #HAM_SLOW_ROWS-1,d5      ; d5 = slow rows remaining after current row
        movea.l a0,a3                    ; a3 = slow plane 0 write pointer
        lea     HAM_SLOW_ROW_CACHE_PLANE_BYTES(a3),a4 ; a4 = slow plane 1 write pointer
        lea     HAM_SLOW_ROW_CACHE_PLANE_BYTES(a4),a5 ; a5 = slow plane 2 write pointer
        lea     HAM_SLOW_ROW_CACHE_PLANE_BYTES(a5),a0 ; a0 = slow plane 3 write pointer
        bra.w   RenderHamRowsCore         ; render rows through the shared inline core

; Shared multi-row renderer. It keeps the row body inline and uses d5 as row counter.

RenderHamRowsCore:
        move.w  d1,d6                     ; pair 1: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 1: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 1: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 1: advance U to cell B
        add.w   d3,d1                     ; pair 1: advance V to cell B
        move.w  d1,d7                     ; pair 1: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 1: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 1: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 1: advance U to next pair
        add.w   d3,d1                     ; pair 1: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 1: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 1: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 1: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 1: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 1: write plane 1 byte
        swap    d4                        ; pair 1: select upper plane word
        move.b  d4,(a5)+                  ; pair 1: write plane 2 byte
        lsr.w   #8,d4                     ; pair 1: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 1: write plane 3 byte

        move.w  d1,d6                     ; pair 2: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 2: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 2: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 2: advance U to cell B
        add.w   d3,d1                     ; pair 2: advance V to cell B
        move.w  d1,d7                     ; pair 2: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 2: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 2: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 2: advance U to next pair
        add.w   d3,d1                     ; pair 2: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 2: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 2: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 2: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 2: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 2: write plane 1 byte
        swap    d4                        ; pair 2: select upper plane word
        move.b  d4,(a5)+                  ; pair 2: write plane 2 byte
        lsr.w   #8,d4                     ; pair 2: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 2: write plane 3 byte

        move.w  d1,d6                     ; pair 3: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 3: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 3: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 3: advance U to cell B
        add.w   d3,d1                     ; pair 3: advance V to cell B
        move.w  d1,d7                     ; pair 3: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 3: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 3: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 3: advance U to next pair
        add.w   d3,d1                     ; pair 3: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 3: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 3: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 3: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 3: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 3: write plane 1 byte
        swap    d4                        ; pair 3: select upper plane word
        move.b  d4,(a5)+                  ; pair 3: write plane 2 byte
        lsr.w   #8,d4                     ; pair 3: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 3: write plane 3 byte

        move.w  d1,d6                     ; pair 4: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 4: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 4: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 4: advance U to cell B
        add.w   d3,d1                     ; pair 4: advance V to cell B
        move.w  d1,d7                     ; pair 4: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 4: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 4: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 4: advance U to next pair
        add.w   d3,d1                     ; pair 4: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 4: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 4: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 4: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 4: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 4: write plane 1 byte
        swap    d4                        ; pair 4: select upper plane word
        move.b  d4,(a5)+                  ; pair 4: write plane 2 byte
        lsr.w   #8,d4                     ; pair 4: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 4: write plane 3 byte

        move.w  d1,d6                     ; pair 5: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 5: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 5: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 5: advance U to cell B
        add.w   d3,d1                     ; pair 5: advance V to cell B
        move.w  d1,d7                     ; pair 5: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 5: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 5: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 5: advance U to next pair
        add.w   d3,d1                     ; pair 5: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 5: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 5: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 5: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 5: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 5: write plane 1 byte
        swap    d4                        ; pair 5: select upper plane word
        move.b  d4,(a5)+                  ; pair 5: write plane 2 byte
        lsr.w   #8,d4                     ; pair 5: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 5: write plane 3 byte

        move.w  d1,d6                     ; pair 6: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 6: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 6: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 6: advance U to cell B
        add.w   d3,d1                     ; pair 6: advance V to cell B
        move.w  d1,d7                     ; pair 6: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 6: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 6: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 6: advance U to next pair
        add.w   d3,d1                     ; pair 6: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 6: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 6: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 6: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 6: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 6: write plane 1 byte
        swap    d4                        ; pair 6: select upper plane word
        move.b  d4,(a5)+                  ; pair 6: write plane 2 byte
        lsr.w   #8,d4                     ; pair 6: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 6: write plane 3 byte

        move.w  d1,d6                     ; pair 7: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 7: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 7: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 7: advance U to cell B
        add.w   d3,d1                     ; pair 7: advance V to cell B
        move.w  d1,d7                     ; pair 7: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 7: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 7: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 7: advance U to next pair
        add.w   d3,d1                     ; pair 7: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 7: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 7: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 7: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 7: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 7: write plane 1 byte
        swap    d4                        ; pair 7: select upper plane word
        move.b  d4,(a5)+                  ; pair 7: write plane 2 byte
        lsr.w   #8,d4                     ; pair 7: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 7: write plane 3 byte

        move.w  d1,d6                     ; pair 8: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 8: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 8: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 8: advance U to cell B
        add.w   d3,d1                     ; pair 8: advance V to cell B
        move.w  d1,d7                     ; pair 8: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 8: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 8: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 8: advance U to next pair
        add.w   d3,d1                     ; pair 8: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 8: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 8: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 8: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 8: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 8: write plane 1 byte
        swap    d4                        ; pair 8: select upper plane word
        move.b  d4,(a5)+                  ; pair 8: write plane 2 byte
        lsr.w   #8,d4                     ; pair 8: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 8: write plane 3 byte

        move.w  d1,d6                     ; pair 9: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 9: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 9: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 9: advance U to cell B
        add.w   d3,d1                     ; pair 9: advance V to cell B
        move.w  d1,d7                     ; pair 9: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 9: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 9: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 9: advance U to next pair
        add.w   d3,d1                     ; pair 9: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 9: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 9: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 9: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 9: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 9: write plane 1 byte
        swap    d4                        ; pair 9: select upper plane word
        move.b  d4,(a5)+                  ; pair 9: write plane 2 byte
        lsr.w   #8,d4                     ; pair 9: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 9: write plane 3 byte

        move.w  d1,d6                     ; pair 10: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 10: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 10: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 10: advance U to cell B
        add.w   d3,d1                     ; pair 10: advance V to cell B
        move.w  d1,d7                     ; pair 10: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 10: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 10: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 10: advance U to next pair
        add.w   d3,d1                     ; pair 10: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 10: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 10: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 10: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 10: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 10: write plane 1 byte
        swap    d4                        ; pair 10: select upper plane word
        move.b  d4,(a5)+                  ; pair 10: write plane 2 byte
        lsr.w   #8,d4                     ; pair 10: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 10: write plane 3 byte

        move.w  d1,d6                     ; pair 11: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 11: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 11: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 11: advance U to cell B
        add.w   d3,d1                     ; pair 11: advance V to cell B
        move.w  d1,d7                     ; pair 11: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 11: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 11: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 11: advance U to next pair
        add.w   d3,d1                     ; pair 11: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 11: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 11: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 11: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 11: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 11: write plane 1 byte
        swap    d4                        ; pair 11: select upper plane word
        move.b  d4,(a5)+                  ; pair 11: write plane 2 byte
        lsr.w   #8,d4                     ; pair 11: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 11: write plane 3 byte

        move.w  d1,d6                     ; pair 12: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 12: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 12: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 12: advance U to cell B
        add.w   d3,d1                     ; pair 12: advance V to cell B
        move.w  d1,d7                     ; pair 12: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 12: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 12: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 12: advance U to next pair
        add.w   d3,d1                     ; pair 12: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 12: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 12: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 12: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 12: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 12: write plane 1 byte
        swap    d4                        ; pair 12: select upper plane word
        move.b  d4,(a5)+                  ; pair 12: write plane 2 byte
        lsr.w   #8,d4                     ; pair 12: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 12: write plane 3 byte

        move.w  d1,d6                     ; pair 13: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 13: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 13: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 13: advance U to cell B
        add.w   d3,d1                     ; pair 13: advance V to cell B
        move.w  d1,d7                     ; pair 13: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 13: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 13: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 13: advance U to next pair
        add.w   d3,d1                     ; pair 13: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 13: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 13: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 13: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 13: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 13: write plane 1 byte
        swap    d4                        ; pair 13: select upper plane word
        move.b  d4,(a5)+                  ; pair 13: write plane 2 byte
        lsr.w   #8,d4                     ; pair 13: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 13: write plane 3 byte

        move.w  d1,d6                     ; pair 14: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 14: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 14: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 14: advance U to cell B
        add.w   d3,d1                     ; pair 14: advance V to cell B
        move.w  d1,d7                     ; pair 14: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 14: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 14: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 14: advance U to next pair
        add.w   d3,d1                     ; pair 14: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 14: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 14: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 14: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 14: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 14: write plane 1 byte
        swap    d4                        ; pair 14: select upper plane word
        move.b  d4,(a5)+                  ; pair 14: write plane 2 byte
        lsr.w   #8,d4                     ; pair 14: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 14: write plane 3 byte

        move.w  d1,d6                     ; pair 15: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 15: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 15: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 15: advance U to cell B
        add.w   d3,d1                     ; pair 15: advance V to cell B
        move.w  d1,d7                     ; pair 15: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 15: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 15: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 15: advance U to next pair
        add.w   d3,d1                     ; pair 15: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 15: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 15: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 15: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 15: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 15: write plane 1 byte
        swap    d4                        ; pair 15: select upper plane word
        move.b  d4,(a5)+                  ; pair 15: write plane 2 byte
        lsr.w   #8,d4                     ; pair 15: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 15: write plane 3 byte

        move.w  d1,d6                     ; pair 16: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 16: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 16: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 16: advance U to cell B
        add.w   d3,d1                     ; pair 16: advance V to cell B
        move.w  d1,d7                     ; pair 16: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 16: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 16: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 16: advance U to next pair
        add.w   d3,d1                     ; pair 16: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 16: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 16: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 16: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 16: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 16: write plane 1 byte
        swap    d4                        ; pair 16: select upper plane word
        move.b  d4,(a5)+                  ; pair 16: write plane 2 byte
        lsr.w   #8,d4                     ; pair 16: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 16: write plane 3 byte

        move.w  d1,d6                     ; pair 17: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 17: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 17: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 17: advance U to cell B
        add.w   d3,d1                     ; pair 17: advance V to cell B
        move.w  d1,d7                     ; pair 17: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 17: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 17: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 17: advance U to next pair
        add.w   d3,d1                     ; pair 17: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 17: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 17: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 17: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 17: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 17: write plane 1 byte
        swap    d4                        ; pair 17: select upper plane word
        move.b  d4,(a5)+                  ; pair 17: write plane 2 byte
        lsr.w   #8,d4                     ; pair 17: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 17: write plane 3 byte

        move.w  d1,d6                     ; pair 18: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 18: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 18: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 18: advance U to cell B
        add.w   d3,d1                     ; pair 18: advance V to cell B
        move.w  d1,d7                     ; pair 18: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 18: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 18: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 18: advance U to next pair
        add.w   d3,d1                     ; pair 18: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 18: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 18: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 18: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 18: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 18: write plane 1 byte
        swap    d4                        ; pair 18: select upper plane word
        move.b  d4,(a5)+                  ; pair 18: write plane 2 byte
        lsr.w   #8,d4                     ; pair 18: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 18: write plane 3 byte

        move.w  d1,d6                     ; pair 19: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 19: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 19: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 19: advance U to cell B
        add.w   d3,d1                     ; pair 19: advance V to cell B
        move.w  d1,d7                     ; pair 19: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 19: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 19: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 19: advance U to next pair
        add.w   d3,d1                     ; pair 19: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 19: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 19: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 19: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 19: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 19: write plane 1 byte
        swap    d4                        ; pair 19: select upper plane word
        move.b  d4,(a5)+                  ; pair 19: write plane 2 byte
        lsr.w   #8,d4                     ; pair 19: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 19: write plane 3 byte

        move.w  d1,d6                     ; pair 20: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 20: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 20: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 20: advance U to cell B
        add.w   d3,d1                     ; pair 20: advance V to cell B
        move.w  d1,d7                     ; pair 20: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 20: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 20: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 20: advance U to next pair
        add.w   d3,d1                     ; pair 20: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 20: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 20: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 20: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 20: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 20: write plane 1 byte
        swap    d4                        ; pair 20: select upper plane word
        move.b  d4,(a5)+                  ; pair 20: write plane 2 byte
        lsr.w   #8,d4                     ; pair 20: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 20: write plane 3 byte

        move.w  d1,d6                     ; pair 21: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 21: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 21: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 21: advance U to cell B
        add.w   d3,d1                     ; pair 21: advance V to cell B
        move.w  d1,d7                     ; pair 21: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 21: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 21: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 21: advance U to next pair
        add.w   d3,d1                     ; pair 21: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 21: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 21: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 21: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 21: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 21: write plane 1 byte
        swap    d4                        ; pair 21: select upper plane word
        move.b  d4,(a5)+                  ; pair 21: write plane 2 byte
        lsr.w   #8,d4                     ; pair 21: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 21: write plane 3 byte

        move.w  d1,d6                     ; pair 22: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 22: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 22: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 22: advance U to cell B
        add.w   d3,d1                     ; pair 22: advance V to cell B
        move.w  d1,d7                     ; pair 22: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 22: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 22: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 22: advance U to next pair
        add.w   d3,d1                     ; pair 22: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 22: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 22: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 22: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 22: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 22: write plane 1 byte
        swap    d4                        ; pair 22: select upper plane word
        move.b  d4,(a5)+                  ; pair 22: write plane 2 byte
        lsr.w   #8,d4                     ; pair 22: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 22: write plane 3 byte

        move.w  d1,d6                     ; pair 23: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 23: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 23: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 23: advance U to cell B
        add.w   d3,d1                     ; pair 23: advance V to cell B
        move.w  d1,d7                     ; pair 23: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 23: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 23: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 23: advance U to next pair
        add.w   d3,d1                     ; pair 23: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 23: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 23: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 23: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 23: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 23: write plane 1 byte
        swap    d4                        ; pair 23: select upper plane word
        move.b  d4,(a5)+                  ; pair 23: write plane 2 byte
        lsr.w   #8,d4                     ; pair 23: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 23: write plane 3 byte

        move.w  d1,d6                     ; pair 24: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 24: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 24: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 24: advance U to cell B
        add.w   d3,d1                     ; pair 24: advance V to cell B
        move.w  d1,d7                     ; pair 24: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 24: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 24: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 24: advance U to next pair
        add.w   d3,d1                     ; pair 24: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 24: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 24: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 24: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 24: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 24: write plane 1 byte
        swap    d4                        ; pair 24: select upper plane word
        move.b  d4,(a5)+                  ; pair 24: write plane 2 byte
        lsr.w   #8,d4                     ; pair 24: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 24: write plane 3 byte

        move.w  d1,d6                     ; pair 25: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 25: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 25: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 25: advance U to cell B
        add.w   d3,d1                     ; pair 25: advance V to cell B
        move.w  d1,d7                     ; pair 25: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 25: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 25: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 25: advance U to next pair
        add.w   d3,d1                     ; pair 25: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 25: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 25: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 25: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 25: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 25: write plane 1 byte
        swap    d4                        ; pair 25: select upper plane word
        move.b  d4,(a5)+                  ; pair 25: write plane 2 byte
        lsr.w   #8,d4                     ; pair 25: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 25: write plane 3 byte

        move.w  d1,d6                     ; pair 26: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 26: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 26: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 26: advance U to cell B
        add.w   d3,d1                     ; pair 26: advance V to cell B
        move.w  d1,d7                     ; pair 26: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 26: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 26: load RGB4 table offset for cell B
        move.l  (a6,d6.w),d4              ; pair 26: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 26: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 26: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 26: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 26: write plane 1 byte
        swap    d4                        ; pair 26: select upper plane word
        move.b  d4,(a5)+                  ; pair 26: write plane 2 byte
        lsr.w   #8,d4                     ; pair 26: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 26: write plane 3 byte
        dbra    d5,RenderHamRowsCoreDelta ; branch when another row follows
        movem.l (sp)+,d4-d7/a3-a6        ; restore clobbered C registers only
        rts                              ; return to C
RenderHamRowsCoreDelta:
RenderHamRowsCoreRowUDelta:
        add.w   #0,d0                    ; advance U to next rendered row
RenderHamRowsCoreRowVDelta:
        add.w   #0,d1                    ; advance V to next rendered row
        bra.w   RenderHamRowsCore        ; render next row inline
