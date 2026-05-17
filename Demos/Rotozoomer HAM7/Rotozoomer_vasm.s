;*************************************************************************
;* 4x4 HAM7 BPLDAT Quirk Rotozoomer ASM Renderer                         *
;*                                                                       *
;* 56x52 hybrid row cache renderer. Rows below the dynamic band use      *
;* half-rate and direct slow-row caches according to the shared limits.  *
;* Runtime draws rows 0-1 and the configured temporal band directly.     *
;* BPL5DAT/BPL6DAT control words are handled by the Copperlist in C.     *
;*************************************************************************

        machine 68000

	include	"lwmf/lwmf_hardware_regs.i"

	include	"Rotozoomer_shared.i"

HAM_LOOP_CTX_UOFFSET_MID             equ     4
HAM_LOOP_CTX_PAIR_TABLES_BASE        equ     8
HAM_LOOP_CTX_FRAME_PARAMS            equ     12
HAM_LOOP_CTX_HALF_COPPER_WORDS       equ     16
HAM_LOOP_CTX_HAM0                    equ     20
HAM_LOOP_CTX_HAM1                    equ     24
HAM_LOOP_CTX_COPPER0                 equ     28
HAM_LOOP_CTX_COPPER1                 equ     32

HAM_FRAME_DUDX                       equ     0
HAM_FRAME_DVDX                       equ     2
HAM_FRAME_ROWU                       equ     4
HAM_FRAME_ROWV                       equ     6
HAM_FRAME_ROWUDELTA                 equ     8
HAM_FRAME_ROWVDELTA                 equ     10
HAM_FRAME_UPPER_ROWU                equ     12
HAM_FRAME_UPPER_ROWV                equ     14
HAM_FRAME_LOWER_ROWU                equ     16
HAM_FRAME_LOWER_ROWV                equ     18
HAM_FRAME_PHASE_STEP_BYTES          equ     HAM_ANGLE_PHASE_STEP*20
HAM_LOOP_PHASE_STEP                  equ     HAM_ANGLE_PHASE_STEP+HAM_ANGLE_PHASE_STEP
HAM_LOOP_PHASE_STEP_BYTES           equ     HAM_LOOP_PHASE_STEP*20

CIAA_PRA                             equ     $00BFE001

; void InitHamBlitterCopyModeAsm(void)
; Initializes the fixed A-to-D blitter mode and full source masks.

_InitHamBlitterCopyModeAsm::
.bwi:   btst.b  #DMAB_BLITTER,DMACONR     ; wait before changing blitter copy state
        bne.s   .bwi                      ; loop while blitter is busy
        move.l  #(BLTCON0_COPY_A_TO_D<<16),BLTCON0 ; set A-to-D copy mode and clear BLTCON1
        move.l  #$FFFFFFFF,BLTAFWM        ; use all bits in first and last source words
        rts                               ; return to C

; void RunHamMainLoopAsm(a0=Context)

_RunHamMainLoopAsm::
        movem.l d2-d7/a2-a6,-(sp)        ; preserve the full vbcc callee-saved register set before returning to C
        movea.l a0,a6                    ; a6 = immutable main-loop context
        move.l  (a6),d6                  ; d6 = invariant TextureCellsMid pointer for render calls
        movea.l (HAM_LOOP_CTX_UOFFSET_MID,a6),a2 ; a2 = invariant wrapped-U lookup table
        movea.l (HAM_LOOP_CTX_PAIR_TABLES_BASE,a6),a3 ; a3 = invariant pair table base
        movea.l (HAM_LOOP_CTX_FRAME_PARAMS,a6),a5 ; a5 = current even-frame params pointer
        movea.l (HAM_LOOP_CTX_HALF_COPPER_WORDS,a6),a4 ; a4 = current cached half-rate copper words
        movea.l (HAM_LOOP_CTX_COPPER1,a6),a0 ; a0 = next even-frame copper list kept across loop tail
        moveq   #0,d5                    ; d5.b = even-frame phase with natural 8-bit wrap
.loop:
        btst.b  #6,CIAA_PRA              ; left mouse button exits when pressed
        beq     .done                    ; leave the effect loop on click

        bsr     WaitHamLiveDoneAndSwitchCopper

        move.w  (a5),d4                 ; d4 = even-frame DuDx cached across both renders
        move.w  (HAM_FRAME_DVDX,a5),d7  ; d7 = even-frame DvDx cached across both renders
        move.w  (HAM_FRAME_ROWUDELTA,a5),d1 ; d1 = precomputed row U delta
        lea     RenderHamRowsCoreRowUDelta+2(pc),a0 ; patch both shared row deltas from one base slot
        move.w  d1,(a0)
        move.w  (HAM_FRAME_ROWVDELTA,a5),d1 ; d1 = precomputed row V delta
        move.w  d1,4(a0)

        movea.l (HAM_LOOP_CTX_HAM0,a6),a0 ; render live rows into dynamic buffer 0
        move.w  (HAM_FRAME_ROWU,a5),d0
        move.w  (HAM_FRAME_ROWV,a5),d1
        move.w  d4,d2
        move.w  d7,d3
        movea.l d6,a1                    ; a1 = invariant TextureCellsMid pointer
        bsr     RenderHamLiveRowsNoPatch

        movea.l (HAM_LOOP_CTX_HAM0,a6),a0 ; copy cached lower temporal rows from buffer 1 to buffer 0
        movea.l (HAM_LOOP_CTX_HAM1,a6),a1
        bsr     CopyHamTemporalLowerRows

        movea.l (HAM_LOOP_CTX_HAM0,a6),a0 ; render upper temporal rows for the even frame
        move.w  (HAM_FRAME_UPPER_ROWU,a5),d0
        move.w  (HAM_FRAME_UPPER_ROWV,a5),d1
        move.w  d4,d2
        move.w  d7,d3
        movea.l d6,a1                    ; a1 = invariant TextureCellsMid pointer
        bsr     RenderHamTemporalUpperRowsNoPatch

        movea.l (HAM_LOOP_CTX_COPPER0,a6),a0 ; update copper list 0 for the odd frame
        bsr     UpdateHamCachedPointers
        bsr     WaitHamLiveDoneAndSwitchCopper

        lea     HAM_FRAME_PHASE_STEP_BYTES(a5),a1 ; a1 = odd-frame params pointer
        move.w  (a1),d4                 ; d4 = odd-frame DuDx cached across both renders
        move.w  (HAM_FRAME_DVDX,a1),d7  ; d7 = odd-frame DvDx cached across both renders
        move.w  (HAM_FRAME_ROWUDELTA,a1),d1 ; d1 = precomputed row U delta
        lea     RenderHamRowsCoreRowUDelta+2(pc),a0 ; patch both shared row deltas from one base slot
        move.w  d1,(a0)
        move.w  (HAM_FRAME_ROWVDELTA,a1),d1 ; d1 = precomputed row V delta
        move.w  d1,4(a0)

        movea.l (HAM_LOOP_CTX_HAM1,a6),a0 ; render live rows into dynamic buffer 1
        lea     HAM_FRAME_PHASE_STEP_BYTES(a5),a1 ; a1 = odd-frame params pointer
        move.w  (HAM_FRAME_ROWU,a1),d0
        move.w  (HAM_FRAME_ROWV,a1),d1
        move.w  d4,d2
        move.w  d7,d3
        movea.l d6,a1                    ; a1 = invariant TextureCellsMid pointer
        bsr     RenderHamLiveRowsNoPatch

        movea.l (HAM_LOOP_CTX_HAM1,a6),a0 ; copy cached upper temporal rows from buffer 0 to buffer 1
        movea.l (HAM_LOOP_CTX_HAM0,a6),a1
        bsr     CopyHamTemporalUpperRows

        movea.l (HAM_LOOP_CTX_HAM1,a6),a0 ; render lower temporal rows for the odd frame
        lea     HAM_FRAME_PHASE_STEP_BYTES(a5),a1 ; a1 = odd-frame params pointer
        move.w  (HAM_FRAME_LOWER_ROWU,a1),d0
        move.w  (HAM_FRAME_LOWER_ROWV,a1),d1
        move.w  d4,d2
        move.w  d7,d3
        movea.l d6,a1                    ; a1 = invariant TextureCellsMid pointer
        bsr     RenderHamTemporalLowerRowsNoPatch

        movea.l (HAM_LOOP_CTX_COPPER1,a6),a0 ; update copper list 1 for the next even frame
        bsr     UpdateHamCachedPointers

        addi.b  #HAM_LOOP_PHASE_STEP,d5 ; advance to the next even-frame phase
        beq.s   .wrap                    ; restart cyclic pointer streams on 8-bit phase wrap
        lea     HAM_LOOP_PHASE_STEP_BYTES(a5),a5 ; advance to the next even-frame params
        lea     16(a4),a4                ; advance to the next cached half-rate copper words
        bra     .loop
.wrap:
        movea.l (HAM_LOOP_CTX_FRAME_PARAMS,a6),a5 ; restart the frame params stream on wrap
        movea.l (HAM_LOOP_CTX_HALF_COPPER_WORDS,a6),a4
        bra     .loop
.done:
        movem.l (sp)+,d2-d7/a2-a6        ; restore the full vbcc callee-saved register set for the C caller
        rts                               ; return to C for cleanup

; Internal live-done wait and copper switch helper.

WaitHamLiveDoneAndSwitchCopper:
        lea     CUSTOMREGS,a1             ; use custom base for beam and copper access
        move.l  a0,(COP1LCH-CUSTOMREGS,a1) ; prepare copper list for the next frame early
        btst.b  #0,(VPOSR+1-CUSTOMREGS,a1) ; test PAL line bit 8
        bne.s   .done                     ; rendering is safe in lower border/vblank
.wait_live:
        cmp.b   #HAM_CORE_DONE_LOW,(VPOSR+2-CUSTOMREGS,a1) ; wait for first line below core rows
        blo.s   .wait_live                ; stay while the beam still reads core rows
.done:
        rts                               ; return to C

; Internal half-rate pointer update helper.
UpdateHamCachedPointers:
	lea	HAM_COPPER_HALFRATE_BPLPTR_BYTES(a0),a1	; a1 = half-rate pointer value slot while a0 stays reusable
        move.w  (a4),(a1)                ; plane 0 high word
        move.w  2(a4),4(a1)              ; plane 0 low word
        move.w  4(a4),8(a1)              ; plane 1 high word
        move.w  6(a4),12(a1)             ; plane 1 low word
        move.w  8(a4),16(a1)             ; plane 2 high word
        move.w  10(a4),20(a1)            ; plane 2 low word
        move.w  12(a4),24(a1)            ; plane 3 high word
        move.w  14(a4),28(a1)            ; plane 3 low word
	rts					; return without any slow-row blit

; Internal temporal upper-half copy helper.
; Uses blitter for A->D copy of the configured upper temporal half, all 4 planes.
; Returns immediately after firing the tail chunk; the next blitter user waits as needed.
CopyHamTemporalUpperRows:
        moveq   #HAM_TEMPORAL_UPPER_DEST_OFFSET,d2 ; upper rows start at the small upper offset
        bra.s   CopyHamTemporalRowsCore  ; share the same blitter sequence with the lower half

; Internal temporal lower-half copy helper.
; Uses blitter for A->D copy of the configured lower temporal half, all 4 planes.
; Returns immediately after firing the tail chunk; the next blitter user waits as needed.
CopyHamTemporalLowerRows:
        move.w  #HAM_TEMPORAL_LOWER_DEST_OFFSET,d2 ; lower rows start deeper in the dynamic buffer

; Shared temporal blitter copy. d2 holds the byte offset for both source and target halves.

CopyHamTemporalRowsCore:
        adda.w  d2,a0                    ; target will start at the requested temporal half
        adda.w  d2,a1                    ; source will start at the requested temporal half
        move.l  a0,d0                    ; d0 = destination chunk pointer
        move.l  a1,d1                    ; d1 = source chunk pointer
        lea     CUSTOMREGS,a0             ; use custom base without a callee-saved register
        move.w  #BLTPRI_SET,(DMACON-CUSTOMREGS,a0) ; give blitter priority while this routine waits
.bwt0:  btst.b  #DMAB_BLITTER,(DMACONR-CUSTOMREGS,a0) ; wait for any previous blit to finish
        bne.s   .bwt0                     ; loop while busy
        move.l  #BLIT_TEMPORAL_WIDE_MOD_LONG,(BLTAMOD-CUSTOMREGS,a0) ; set source and dest wide modulos
        move.l  d1,(BLTAPTH-CUSTOMREGS,a0) ; chunk 0: write source pointer
        move.l  d0,(BLTDPTH-CUSTOMREGS,a0) ; chunk 0: write destination pointer
        move.w  #BLIT_TEMPORAL_WIDE_SIZE,(BLTSIZE-CUSTOMREGS,a0) ; fire chunk 0 for all planes
        add.l   #BLIT_TEMPORAL_WIDE_BYTES,d0 ; advance dest to tail chunk
        add.l   #BLIT_TEMPORAL_WIDE_BYTES,d1 ; advance source to tail chunk
.bwt1:  btst.b  #DMAB_BLITTER,(DMACONR-CUSTOMREGS,a0) ; wait for the wide chunk blit done
        bne.s   .bwt1                     ; loop while busy
        move.l  #BLIT_TEMPORAL_TAIL_MOD_LONG,(BLTAMOD-CUSTOMREGS,a0) ; set source and dest tail modulos
        move.l  d1,(BLTAPTH-CUSTOMREGS,a0) ; tail chunk: write source pointer
        move.l  d0,(BLTDPTH-CUSTOMREGS,a0) ; tail chunk: write destination pointer
        move.w  #BLTPRI_CLR,(DMACON-CUSTOMREGS,a0) ; let final chunk overlap with CPU work
        move.w  #BLIT_TEMPORAL_TAIL_SIZE,(BLTSIZE-CUSTOMREGS,a0) ; fire tail chunk for all planes
        rts                              ; tail blit runs in parallel with CPU

RenderHamTemporalUpperRowsNoPatch:
        btst.b  #0,VPOSR+1                ; test PAL line bit 8 before touching temporal rows
        bne.s   .temporal_render_safe_np  ; rendering is safe in lower border/vblank
.wait_temporal_render_np:
        cmp.b   #HAM_TEMPORAL_UPPER_DONE_LOW,VPOSR+2 ; wait for first line below this temporal half
        blo.s   .wait_temporal_render_np  ; stay while the beam still reads those rows
.temporal_render_safe_np:
        movem.l d4-d7/a3-a6,-(sp)        ; save clobbered C registers only
        moveq   #HAM_TEMPORAL_UPPER_DEST_OFFSET,d4 ; upper rows start at the small temporal offset
RenderHamTemporalRowsSetupNoPatch:
        movea.l a3,a6                    ; a6 = interleaved pair table base
        adda.w  d4,a0                    ; advance base to the requested temporal half
        moveq   #HAM_TEMPORAL_HALF_ROWS-1,d5 ; d5 = temporal rows remaining after current row
        movea.l a0,a3                    ; a3 = temporal plane 0 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a3),a4 ; a4 = temporal plane 1 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a4),a5 ; a5 = temporal plane 2 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a5),a0 ; a0 = temporal plane 3 write pointer
        bra     RenderHamRowsCore         ; render rows without per-row subroutine calls

RenderHamLiveRowsNoPatch:
        movem.l d4-d7/a3-a6,-(sp)        ; save clobbered C registers only
        moveq   #HAM_LIVE_ROWS-1,d5      ; d5 = live rows remaining after current row
        movea.l a3,a6                    ; a6 = interleaved pair table base
        movea.l a0,a3                    ; a3 = plane 0 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a3),a4 ; a4 = plane 1 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a4),a5 ; a5 = plane 2 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a5),a0 ; a0 = plane 3 write pointer
        bra.s   RenderHamRowsCore         ; render rows through the shared inline core

; void RenderHamHalfRowsAsm(a0=Base, a1=TextureCellsMid, a2=UOffsetTableMid,
;                             a3=PairTables, d0=RowU, d1=RowV,
;                             d2=DuDx, d3=DvDx, d6=RowUDelta, d7=RowVDelta)

_RenderHamHalfRowsAsm::
        movem.l d4-d7/a3-a6,-(sp)        ; save clobbered C registers only
        moveq   #HAM_HALFRATE_ROWS-1,d5  ; d5 = half-rate rows remaining after current row
RenderHamRowsSetup:
        lea     RenderHamRowsCoreRowUDelta+2(pc),a5 ; get shared row U delta immediate
        move.w  d6,(a5)                  ; patch row U delta from frame params
        move.w  d7,4(a5)                 ; patch row V delta from the adjacent immediate slot
        movea.l a3,a6                    ; a6 = interleaved pair table base
        movea.l a0,a3                    ; a3 = plane 0 write pointer
        lea     HAM_HALFRATE_ROW_CACHE_PLANE_BYTES(a3),a4 ; a4 = plane 1 write pointer
        lea     HAM_HALFRATE_ROW_CACHE_PLANE_BYTES(a4),a5 ; a5 = plane 2 write pointer
        lea     HAM_HALFRATE_ROW_CACHE_PLANE_BYTES(a5),a0 ; a0 = plane 3 write pointer
        bra     RenderHamRowsCore         ; render rows through the shared inline core

RenderHamTemporalLowerRowsNoPatch:
        btst.b  #0,VPOSR+1                ; test PAL line bit 8 before touching temporal rows
        bne.s   .temporal_render_safe_np2 ; rendering is safe in lower border/vblank
.wait_temporal_render_np2:
        cmp.b   #HAM_TEMPORAL_DONE_LOW,VPOSR+2 ; wait for first line below this temporal half
        blo.s   .wait_temporal_render_np2 ; stay while the beam still reads those rows
.temporal_render_safe_np2:
        movem.l d4-d7/a3-a6,-(sp)        ; save clobbered C registers only
        move.w  #HAM_TEMPORAL_LOWER_DEST_OFFSET,d4 ; lower rows start deeper in the dynamic buffer
        bra     RenderHamTemporalRowsSetupNoPatch ; main loop already patched row deltas

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
        add.w   d2,d0                     ; pair 26: advance U to next pair
        add.w   d3,d1                     ; pair 26: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 26: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 26: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 26: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 26: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 26: write plane 1 byte
        swap    d4                        ; pair 26: select upper plane word
        move.b  d4,(a5)+                  ; pair 26: write plane 2 byte
        lsr.w   #8,d4                     ; pair 26: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 26: write plane 3 byte

        move.w  d1,d6                     ; pair 27: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 27: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 27: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 27: advance U to cell B
        add.w   d3,d1                     ; pair 27: advance V to cell B
        move.w  d1,d7                     ; pair 27: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 27: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 27: load RGB4 table offset for cell B
        add.w   d2,d0                     ; pair 27: advance U to next pair
        add.w   d3,d1                     ; pair 27: advance V to next pair
        move.l  (a6,d6.w),d4              ; pair 27: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 27: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 27: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 27: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 27: write plane 1 byte
        swap    d4                        ; pair 27: select upper plane word
        move.b  d4,(a5)+                  ; pair 27: write plane 2 byte
        lsr.w   #8,d4                     ; pair 27: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 27: write plane 3 byte

        move.w  d1,d6                     ; pair 28: copy V for cell A
        move.b  (a2,d0.w),d6              ; pair 28: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6              ; pair 28: load RGB4 table offset for cell A
        add.w   d2,d0                     ; pair 28: advance U to cell B
        add.w   d3,d1                     ; pair 28: advance V to cell B
        move.w  d1,d7                     ; pair 28: copy V for cell B
        move.b  (a2,d0.w),d7              ; pair 28: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7              ; pair 28: load RGB4 table offset for cell B
        move.l  (a6,d6.w),d4              ; pair 28: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4             ; pair 28: merge four low-nibble plane bytes
        move.b  d4,(a3)+                  ; pair 28: write plane 0 byte and advance
        lsr.w   #8,d4                     ; pair 28: select plane 1 byte
        move.b  d4,(a4)+                  ; pair 28: write plane 1 byte
        swap    d4                        ; pair 28: select upper plane word
        move.b  d4,(a5)+                  ; pair 28: write plane 2 byte
        lsr.w   #8,d4                     ; pair 28: select plane 3 byte
        move.b  d4,(a0)+                  ; pair 28: write plane 3 byte
        dbra    d5,RenderHamRowsCoreDelta ; branch when another row follows
        movem.l (sp)+,d4-d7/a3-a6        ; restore clobbered C registers only
        rts                              ; return to C
RenderHamRowsCoreDelta:
RenderHamRowsCoreRowUDelta:
        add.w   #0,d0                    ; advance U to next rendered row
RenderHamRowsCoreRowVDelta:
        add.w   #0,d1                    ; advance V to next rendered row
        bra.w   RenderHamRowsCore        ; render next row inline
