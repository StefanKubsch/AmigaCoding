;*************************************************************************
;* 4x4 HAM7 BPLDAT Quirk Rotozoomer ASM Renderer - OCS build             *
;*                                                                       *
;* 56x52 hybrid row cache renderer. Rows below the dynamic band use      *
;* a half-rate chip cache according to the shared limits.                *
;* The Copper splices both temporal halves directly from their buffers,   *
;* so the runtime path renders only the rows that actually change.        *
;* OCS uses the BPLDAT quirk for fixed HAM control data.                  *
;*************************************************************************


        machine 68000                                                          ; assemble for plain 68000 code generation

        include "lwmf/lwmf_hardware_regs.i"                                   ; import custom-register and LVO constants

        include "Rotozoomer_shared.i"                                         ; import shared effect constants

HAM_LOOP_CTX_UOFFSET_MID             equ     4                                 ; HamMainLoopContext.UOffsetMid offset
HAM_LOOP_CTX_PAIR_TABLES_BASE        equ     8                                 ; HamMainLoopContext.PairTablesBase offset
HAM_LOOP_CTX_FRAME_PARAMS            equ     12                                ; HamMainLoopContext.FrameParams offset
HAM_LOOP_CTX_HALFRATE_CACHE_BASE     equ     16                                ; HamMainLoopContext.HalfFrameCacheBase offset
HAM_LOOP_CTX_HAM0                    equ     20                                ; HamMainLoopContext.Ham0 offset
HAM_LOOP_CTX_HAM1                    equ     24                                ; HamMainLoopContext.Ham1 offset
HAM_LOOP_CTX_COPPER0                 equ     28                                ; HamMainLoopContext.Copper0 offset
HAM_LOOP_CTX_COPPER1                 equ     32                                ; HamMainLoopContext.Copper1 offset

HAM_FRAME_DUDX                       equ     0                                 ; HamFrameParams.DuDx offset
HAM_FRAME_DVDX                       equ     2                                 ; HamFrameParams.DvDx offset
HAM_FRAME_ROWU                       equ     4                                 ; HamFrameParams.RowU offset
HAM_FRAME_ROWV                       equ     6                                 ; HamFrameParams.RowV offset
HAM_FRAME_ROWUDELTA                  equ     8                                 ; HamFrameParams.RowUDelta offset
HAM_FRAME_ROWVDELTA                  equ     10                                ; HamFrameParams.RowVDelta offset
HAM_FRAME_PHASE_STEP_BYTES           equ     HAM_ANGLE_PHASE_STEP*HAM_FRAME_PARAM_BYTES ; byte distance between adjacent frame param entries
HAM_LOOP_PHASE_STEP                  equ     HAM_ANGLE_PHASE_STEP+HAM_ANGLE_PHASE_STEP ; phase delta from one even frame to the next
HAM_LOOP_PHASE_STEP_BYTES            equ     HAM_LOOP_PHASE_STEP*HAM_FRAME_PARAM_BYTES ; byte distance between consecutive even-frame entries

CIAA_PRA                             equ     $00BFE001                         ; CIA-A port A address for mouse-button polling
; void RunHamMainLoopAsm(a0=Context)

_RunHamMainLoopAsm::                                                           ; export the main HAM renderer loop to C
        movem.l d2-d7/a2-a6,-(sp)                                             ; preserve the full vbcc callee-saved register set before returning to C
        movea.l a0,a6                                                          ; a6 = immutable main-loop context
        move.l  (a6),d6                                                        ; d6 = invariant TextureCellsMid pointer for render calls
        movea.l (HAM_LOOP_CTX_UOFFSET_MID,a6),a2                               ; a2 = invariant wrapped-U lookup table
        movea.l (HAM_LOOP_CTX_PAIR_TABLES_BASE,a6),a3                          ; a3 = invariant compact pair table base
        movea.l (HAM_LOOP_CTX_FRAME_PARAMS,a6),a5                              ; a5 = current even-frame params pointer
        movea.l (HAM_LOOP_CTX_HALFRATE_CACHE_BASE,a6),a4                       ; a4 = current cached half-rate frame bitmap
        movea.l (HAM_LOOP_CTX_COPPER1,a6),a0                                   ; a0 = next even-frame copper list kept across loop tail
        moveq   #0,d5                                                          ; d5.b = even-frame phase with natural 8-bit wrap
.loop:                                                                          ; start the next even/odd frame pair
        btst.b  #6,CIAA_PRA                                                    ; left mouse button exits when pressed
        beq     .done                                                          ; leave the effect loop on click

        bsr     WaitHamLiveDoneAndSwitchCopper                                 ; arm the next copper list and wait until live rows are safe

        movea.l a5,a1                                                          ; a1 = even-frame params for delta patching
        move.w  (HAM_FRAME_DUDX,a1),d4                                         ; d4 = even-frame DuDx cached across both renders
        move.w  (HAM_FRAME_DVDX,a1),d7                                         ; d7 = even-frame DvDx cached across both renders
        bsr     StoreHamRowDeltasFromA1                                        ; store row deltas from the 12-byte frame params

        movea.l (HAM_LOOP_CTX_HAM0,a6),a0                                      ; render live rows into dynamic buffer 0
        move.w  (HAM_FRAME_ROWU,a5),d0                                         ; d0 = even-frame starting U for the live band
        move.w  (HAM_FRAME_ROWV,a5),d1                                         ; d1 = even-frame starting V for the live band
        move.w  d4,d2                                                          ; d2 = even-frame DuDx
        move.w  d7,d3                                                          ; d3 = even-frame DvDx
        movea.l d6,a1                                                          ; a1 = invariant TextureCellsMid pointer
        bsr     RenderHamLiveRows                                             ; draw the top live rows for the even frame

        movea.l (HAM_LOOP_CTX_HAM0,a6),a0                                      ; render upper temporal rows into buffer 0
        move.w  (HAM_FRAME_ROWU,a5),d0                                         ; d0 = even-frame base U
        sub.w   d7,d0                                                          ; move to temporal row 2, step 1 in U
        sub.w   d7,d0                                                          ; move to temporal row 2, step 2 in U
        move.w  (HAM_FRAME_ROWV,a5),d1                                         ; d1 = even-frame base V
        add.w   d4,d1                                                          ; move to temporal row 2, step 1 in V
        add.w   d4,d1                                                          ; move to temporal row 2, step 2 in V
        bsr     RenderHamTemporalUpperRows                                    ; draw rows 2-9; the Copper reuses them directly

        movea.l (HAM_LOOP_CTX_COPPER0,a6),a0                                   ; update copper list 0 for the odd frame
        bsr     UpdateHamCachedPointers                                        ; patch copper 0 to the current cached half-rate frame
        bsr     WaitHamLiveDoneAndSwitchCopper                                 ; arm the odd copper list and wait until live rows are safe

        lea     HAM_FRAME_PHASE_STEP_BYTES(a5),a1                              ; a1 = odd-frame params pointer
        move.w  (HAM_FRAME_DUDX,a1),d4                                         ; d4 = odd-frame DuDx cached across both renders
        move.w  (HAM_FRAME_DVDX,a1),d7                                         ; d7 = odd-frame DvDx cached across both renders
        bsr     StoreHamRowDeltasFromA1                                        ; store row deltas from the 12-byte frame params

        movea.l (HAM_LOOP_CTX_HAM1,a6),a0                                      ; render live rows into dynamic buffer 1
        move.w  (HAM_FRAME_ROWU,a1),d0                                         ; d0 = odd-frame starting U for the live band
        move.w  (HAM_FRAME_ROWV,a1),d1                                         ; d1 = odd-frame starting V for the live band
        move.w  d4,d2                                                          ; d2 = odd-frame DuDx
        move.w  d7,d3                                                          ; d3 = odd-frame DvDx
        movea.l d6,a1                                                          ; a1 = invariant TextureCellsMid pointer
        bsr     RenderHamLiveRows                                             ; draw the top live rows for the odd frame

        movea.l (HAM_LOOP_CTX_HAM1,a6),a0                                      ; render lower temporal rows into buffer 1
        lea     HAM_FRAME_PHASE_STEP_BYTES(a5),a1                              ; a1 = odd-frame params pointer
        move.w  (HAM_FRAME_ROWU,a1),d0                                         ; d0 = odd-frame base U
        move.w  d7,d2                                                          ; d2 = DvDx for row 10 offset
        lsl.w   #3,d2                                                          ; d2 = DvDx*8
        add.w   d7,d2                                                          ; d2 = DvDx*9
        add.w   d7,d2                                                          ; d2 = DvDx*10
        sub.w   d2,d0                                                          ; d0 = lower temporal starting U
        move.w  (HAM_FRAME_ROWV,a1),d1                                         ; d1 = odd-frame base V
        move.w  d4,d2                                                          ; d2 = DuDx for row 10 offset
        lsl.w   #3,d2                                                          ; d2 = DuDx*8
        add.w   d4,d2                                                          ; d2 = DuDx*9
        add.w   d4,d2                                                          ; d2 = DuDx*10
        add.w   d2,d1                                                          ; d1 = lower temporal starting V
        move.w  d4,d2                                                          ; d2 = odd-frame DuDx
        movea.l d6,a1                                                          ; a1 = invariant TextureCellsMid pointer
        bsr     RenderHamTemporalLowerRows                                    ; draw rows 10-17; the Copper reuses them directly

        movea.l (HAM_LOOP_CTX_COPPER1,a6),a0                                   ; update copper list 1 for the next even frame
        bsr     UpdateHamCachedPointers                                        ; patch copper 1 to the current cached half-rate frame

        addq.b  #HAM_LOOP_PHASE_STEP,d5                                        ; advance to the next even-frame phase
        beq.s   .wrap                                                          ; restart cyclic pointer streams on 8-bit phase wrap
        lea     HAM_LOOP_PHASE_STEP_BYTES(a5),a5                               ; advance to the next even-frame params
        lea     HAM_HALFRATE_ROW_CACHE_FRAME_BYTES(a4),a4                      ; advance to the next cached half-rate frame
        bra     .loop                                                          ; continue with the next even/odd frame pair
.wrap:                                                                          ; restart phase-dependent pointer streams after byte wraparound
        movea.l (HAM_LOOP_CTX_FRAME_PARAMS,a6),a5                              ; restart the frame params stream on wrap
        movea.l (HAM_LOOP_CTX_HALFRATE_CACHE_BASE,a6),a4                       ; restart the cached half-rate frame stream on wrap
        bra     .loop                                                          ; continue rendering with the wrapped phase state
.done:                                                                          ; begin the controlled shutdown path
        movem.l (sp)+,d2-d7/a2-a6                                             ; restore the full vbcc callee-saved register set for the C caller
        rts                                                                    ; return to C for cleanup

; Internal live-safe wait and copper switch helper.

WaitHamLiveDoneAndSwitchCopper:                                                ; arm the next copper list before waiting for reusable live rows
        lea     CUSTOMREGS,a1                                                  ; use custom base for beam and copper access
        move.l  a0,(COP1LCH-CUSTOMREGS,a1)                                     ; write COP1LC immediately so the next restart sees it
        btst.b  #0,(VPOSR+1-CUSTOMREGS,a1)                                     ; lower border or vblank is already safe
        bne.s   .done                                                          ; skip the visible-area wait in line 256+
.wait_live:                                                                     ; wait until display DMA has passed rows 0-1
        cmp.b   #HAM_CORE_DONE_LOW,(VPOSR+2-CUSTOMREGS,a1)                     ; compare against the first safe line below the live band
        blo.s   .wait_live                                                     ; stay while live rows may still be fetched
.done:                                                                          ; live rows are safe to overwrite
        rts                                                                    ; return to the renderer

; Internal frame-param helper.

StoreHamRowDeltasFromA1:                                                        ; copy precomputed row deltas into cache-safe data storage
        lea     HamRowDeltaVars(pc),a0                                          ; a0 = row-delta variable block
        move.w  (HAM_FRAME_ROWUDELTA,a1),(a0)                                  ; store row U delta from frame params
        move.w  (HAM_FRAME_ROWVDELTA,a1),2(a0)                                 ; store row V delta from frame params
        rts                                                                    ; return with the param pointer intact

; Internal half-rate pointer update helper.

UpdateHamCachedPointers:                                                        ; write four cached half-rate bitplane pointers into the active copper list
        lea     HAM_COPPER_HALFRATE_BPLPTR_BYTES(a0),a1                        ; a1 = half-rate pointer value slot while a0 stays reusable
        move.l  a4,d0                                                          ; d0 = plane 0 pointer
        swap    d0                                                             ; select high word
        move.w  d0,(a1)                                                        ; plane 0 high word
        swap    d0                                                             ; select low word
        move.w  d0,4(a1)                                                       ; plane 0 low word
        add.l   #HAM_HALFRATE_ROW_CACHE_PLANE_BYTES,d0                         ; d0 = plane 1 pointer
        swap    d0                                                             ; select high word
        move.w  d0,8(a1)                                                       ; plane 1 high word
        swap    d0                                                             ; select low word
        move.w  d0,12(a1)                                                      ; plane 1 low word
        add.l   #HAM_HALFRATE_ROW_CACHE_PLANE_BYTES,d0                         ; d0 = plane 2 pointer
        swap    d0                                                             ; select high word
        move.w  d0,16(a1)                                                      ; plane 2 high word
        swap    d0                                                             ; select low word
        move.w  d0,20(a1)                                                      ; plane 2 low word
        add.l   #HAM_HALFRATE_ROW_CACHE_PLANE_BYTES,d0                         ; d0 = plane 3 pointer
        swap    d0                                                             ; select high word
        move.w  d0,24(a1)                                                      ; plane 3 high word
        swap    d0                                                             ; select low word
        move.w  d0,28(a1)                                                      ; plane 3 low word
        rts                                                                    ; return without any temporal blit

RenderHamTemporalUpperRows:                                                   ; render the upper temporal half once the beam has passed it
        btst.b  #0,VPOSR+1                                                     ; test PAL line bit 8 before touching temporal rows
        bne.s   .temporal_render_safe_upper                                   ; rendering is safe in lower border/vblank
.wait_temporal_render_upper:                                                  ; poll until the upper temporal rows are no longer on screen
        cmp.b   #HAM_TEMPORAL_UPPER_DONE_LOW,VPOSR+2                           ; wait for first line below this temporal half
        blo.s   .wait_temporal_render_upper                                   ; stay while the beam still reads those rows
.temporal_render_safe_upper:                                                  ; start the upper temporal render after the visibility window
        movem.l d4-d7/a3-a6,-(sp)                                             ; save clobbered C registers only
        moveq   #HAM_TEMPORAL_UPPER_DEST_OFFSET,d4                             ; upper rows start at the small temporal offset
RenderHamTemporalRowsSetup:                                                   ; common setup for both temporal-half renderers
        movea.l a3,a6                                                          ; a6 = interleaved pair table base
        adda.w  d4,a0                                                          ; advance base to the requested temporal half
        moveq   #HAM_TEMPORAL_HALF_ROWS-1,d5                                   ; d5 = temporal rows remaining after current row
        movea.l a0,a3                                                          ; a3 = temporal plane 0 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a3),a4                                 ; a4 = temporal plane 1 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a4),a5                                 ; a5 = temporal plane 2 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a5),a0                                 ; a0 = temporal plane 3 write pointer
        bra.s   RenderHamRowsCore                                              ; render rows without per-row subroutine calls

RenderHamLiveRows:                                                            ; set up the direct live-row renderer for the live row band
        movem.l d4-d7/a3-a6,-(sp)                                             ; save clobbered C registers only
        moveq   #HAM_LIVE_ROWS-1,d5                                           ; d5 = live rows remaining after current row
        movea.l a3,a6                                                          ; a6 = interleaved pair table base
        movea.l a0,a3                                                          ; a3 = plane 0 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a3),a4                                 ; a4 = plane 1 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a4),a5                                 ; a5 = plane 2 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a5),a0                                 ; a0 = plane 3 write pointer
        bra.s   RenderHamRowsCore                                              ; render rows through the shared inline core

; void RenderHamHalfRowsAsm(a0=Base, a1=TextureCellsMid, a2=UOffsetMid,
;                             a3=PairTables, d0=RowU, d1=RowV,
;                             d2=DuDx, d3=DvDx, d6=RowUDelta, d7=RowVDelta)

_RenderHamHalfRowsAsm::                                                        ; export the half-rate row-cache renderer to C
        movem.l d4-d7/a3-a6,-(sp)                                             ; save clobbered C registers only
        moveq   #HAM_HALFRATE_ROWS-1,d5                                       ; d5 = half-rate rows remaining after current row
        lea     HamRowDeltaVars(pc),a5                                          ; a5 = row-delta variable block
        move.w  d6,(a5)                                                        ; store row U delta as data
        move.w  d7,2(a5)                                                       ; store row V delta as data
        movea.l a3,a6                                                          ; a6 = interleaved pair table base
        movea.l a0,a3                                                          ; a3 = plane 0 write pointer
        lea     HAM_HALFRATE_ROW_CACHE_PLANE_BYTES(a3),a4                      ; a4 = plane 1 write pointer
        lea     HAM_HALFRATE_ROW_CACHE_PLANE_BYTES(a4),a5                      ; a5 = plane 2 write pointer
        lea     HAM_HALFRATE_ROW_CACHE_PLANE_BYTES(a5),a0                      ; a0 = plane 3 write pointer
        bra.s   RenderHamRowsCore                                              ; render rows through the shared inline core

RenderHamTemporalLowerRows:                                                   ; render the lower temporal half once the beam has passed it
        btst.b  #0,VPOSR+1                                                      ; test PAL line bit 8 before touching temporal rows
        bne.s   .temporal_render_safe_lower                                   ; rendering is safe in lower border/vblank
.wait_temporal_render_lower:                                                  ; poll until the lower temporal rows are no longer on screen
        cmp.b   #HAM_TEMPORAL_DONE_LOW,VPOSR+2                                  ; wait for first line below this temporal half
        blo.s   .wait_temporal_render_lower                                   ; stay while the beam still reads those rows
.temporal_render_safe_lower:                                                  ; start the lower temporal render after the visibility window
        movem.l d4-d7/a3-a6,-(sp)                                               ; save clobbered C registers only
        move.w  #HAM_TEMPORAL_LOWER_DEST_OFFSET,d4                              ; lower rows start deeper in the dynamic buffer
        bra.s   RenderHamTemporalRowsSetup                                    ; render through the shared temporal setup

; Shared multi-row renderer. It keeps the row body inline and uses d5 as row counter.

RenderHamRowsCore:									; inline 28-pair row renderer shared by live, temporal, and cache passes
        move.w  d1,d6									; pair 1: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 1: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 1: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 1: advance U to cell B
        add.w   d3,d1									; pair 1: advance V to cell B
        move.w  d1,d7									; pair 1: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 1: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 1: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 1: advance U to next pair
        add.w   d3,d1									; pair 1: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 1: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 1: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 1: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 1: select plane 1 byte
        move.b  d4,(a4)+								; pair 1: write plane 1 byte
        swap    d4									; pair 1: select upper plane word
        move.b  d4,(a5)+								; pair 1: write plane 2 byte
        lsr.w   #8,d4									; pair 1: select plane 3 byte
        move.b  d4,(a0)+								; pair 1: write plane 3 byte

        move.w  d1,d6									; pair 2: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 2: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 2: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 2: advance U to cell B
        add.w   d3,d1									; pair 2: advance V to cell B
        move.w  d1,d7									; pair 2: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 2: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 2: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 2: advance U to next pair
        add.w   d3,d1									; pair 2: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 2: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 2: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 2: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 2: select plane 1 byte
        move.b  d4,(a4)+								; pair 2: write plane 1 byte
        swap    d4									; pair 2: select upper plane word
        move.b  d4,(a5)+								; pair 2: write plane 2 byte
        lsr.w   #8,d4									; pair 2: select plane 3 byte
        move.b  d4,(a0)+								; pair 2: write plane 3 byte

        move.w  d1,d6									; pair 3: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 3: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 3: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 3: advance U to cell B
        add.w   d3,d1									; pair 3: advance V to cell B
        move.w  d1,d7									; pair 3: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 3: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 3: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 3: advance U to next pair
        add.w   d3,d1									; pair 3: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 3: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 3: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 3: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 3: select plane 1 byte
        move.b  d4,(a4)+								; pair 3: write plane 1 byte
        swap    d4									; pair 3: select upper plane word
        move.b  d4,(a5)+								; pair 3: write plane 2 byte
        lsr.w   #8,d4									; pair 3: select plane 3 byte
        move.b  d4,(a0)+								; pair 3: write plane 3 byte

        move.w  d1,d6									; pair 4: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 4: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 4: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 4: advance U to cell B
        add.w   d3,d1									; pair 4: advance V to cell B
        move.w  d1,d7									; pair 4: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 4: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 4: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 4: advance U to next pair
        add.w   d3,d1									; pair 4: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 4: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 4: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 4: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 4: select plane 1 byte
        move.b  d4,(a4)+								; pair 4: write plane 1 byte
        swap    d4									; pair 4: select upper plane word
        move.b  d4,(a5)+								; pair 4: write plane 2 byte
        lsr.w   #8,d4									; pair 4: select plane 3 byte
        move.b  d4,(a0)+								; pair 4: write plane 3 byte

        move.w  d1,d6									; pair 5: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 5: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 5: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 5: advance U to cell B
        add.w   d3,d1									; pair 5: advance V to cell B
        move.w  d1,d7									; pair 5: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 5: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 5: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 5: advance U to next pair
        add.w   d3,d1									; pair 5: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 5: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 5: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 5: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 5: select plane 1 byte
        move.b  d4,(a4)+								; pair 5: write plane 1 byte
        swap    d4									; pair 5: select upper plane word
        move.b  d4,(a5)+								; pair 5: write plane 2 byte
        lsr.w   #8,d4									; pair 5: select plane 3 byte
        move.b  d4,(a0)+								; pair 5: write plane 3 byte

        move.w  d1,d6									; pair 6: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 6: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 6: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 6: advance U to cell B
        add.w   d3,d1									; pair 6: advance V to cell B
        move.w  d1,d7									; pair 6: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 6: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 6: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 6: advance U to next pair
        add.w   d3,d1									; pair 6: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 6: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 6: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 6: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 6: select plane 1 byte
        move.b  d4,(a4)+								; pair 6: write plane 1 byte
        swap    d4									; pair 6: select upper plane word
        move.b  d4,(a5)+								; pair 6: write plane 2 byte
        lsr.w   #8,d4									; pair 6: select plane 3 byte
        move.b  d4,(a0)+								; pair 6: write plane 3 byte

        move.w  d1,d6									; pair 7: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 7: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 7: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 7: advance U to cell B
        add.w   d3,d1									; pair 7: advance V to cell B
        move.w  d1,d7									; pair 7: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 7: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 7: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 7: advance U to next pair
        add.w   d3,d1									; pair 7: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 7: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 7: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 7: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 7: select plane 1 byte
        move.b  d4,(a4)+								; pair 7: write plane 1 byte
        swap    d4									; pair 7: select upper plane word
        move.b  d4,(a5)+								; pair 7: write plane 2 byte
        lsr.w   #8,d4									; pair 7: select plane 3 byte
        move.b  d4,(a0)+								; pair 7: write plane 3 byte

        move.w  d1,d6									; pair 8: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 8: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 8: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 8: advance U to cell B
        add.w   d3,d1									; pair 8: advance V to cell B
        move.w  d1,d7									; pair 8: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 8: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 8: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 8: advance U to next pair
        add.w   d3,d1									; pair 8: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 8: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 8: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 8: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 8: select plane 1 byte
        move.b  d4,(a4)+								; pair 8: write plane 1 byte
        swap    d4									; pair 8: select upper plane word
        move.b  d4,(a5)+								; pair 8: write plane 2 byte
        lsr.w   #8,d4									; pair 8: select plane 3 byte
        move.b  d4,(a0)+								; pair 8: write plane 3 byte

        move.w  d1,d6									; pair 9: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 9: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 9: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 9: advance U to cell B
        add.w   d3,d1									; pair 9: advance V to cell B
        move.w  d1,d7									; pair 9: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 9: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 9: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 9: advance U to next pair
        add.w   d3,d1									; pair 9: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 9: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 9: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 9: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 9: select plane 1 byte
        move.b  d4,(a4)+								; pair 9: write plane 1 byte
        swap    d4									; pair 9: select upper plane word
        move.b  d4,(a5)+								; pair 9: write plane 2 byte
        lsr.w   #8,d4									; pair 9: select plane 3 byte
        move.b  d4,(a0)+								; pair 9: write plane 3 byte

        move.w  d1,d6									; pair 10: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 10: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 10: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 10: advance U to cell B
        add.w   d3,d1									; pair 10: advance V to cell B
        move.w  d1,d7									; pair 10: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 10: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 10: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 10: advance U to next pair
        add.w   d3,d1									; pair 10: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 10: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 10: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 10: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 10: select plane 1 byte
        move.b  d4,(a4)+								; pair 10: write plane 1 byte
        swap    d4									; pair 10: select upper plane word
        move.b  d4,(a5)+								; pair 10: write plane 2 byte
        lsr.w   #8,d4									; pair 10: select plane 3 byte
        move.b  d4,(a0)+								; pair 10: write plane 3 byte

        move.w  d1,d6									; pair 11: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 11: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 11: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 11: advance U to cell B
        add.w   d3,d1									; pair 11: advance V to cell B
        move.w  d1,d7									; pair 11: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 11: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 11: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 11: advance U to next pair
        add.w   d3,d1									; pair 11: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 11: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 11: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 11: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 11: select plane 1 byte
        move.b  d4,(a4)+								; pair 11: write plane 1 byte
        swap    d4									; pair 11: select upper plane word
        move.b  d4,(a5)+								; pair 11: write plane 2 byte
        lsr.w   #8,d4									; pair 11: select plane 3 byte
        move.b  d4,(a0)+								; pair 11: write plane 3 byte

        move.w  d1,d6									; pair 12: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 12: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 12: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 12: advance U to cell B
        add.w   d3,d1									; pair 12: advance V to cell B
        move.w  d1,d7									; pair 12: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 12: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 12: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 12: advance U to next pair
        add.w   d3,d1									; pair 12: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 12: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 12: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 12: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 12: select plane 1 byte
        move.b  d4,(a4)+								; pair 12: write plane 1 byte
        swap    d4									; pair 12: select upper plane word
        move.b  d4,(a5)+								; pair 12: write plane 2 byte
        lsr.w   #8,d4									; pair 12: select plane 3 byte
        move.b  d4,(a0)+								; pair 12: write plane 3 byte

        move.w  d1,d6									; pair 13: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 13: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 13: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 13: advance U to cell B
        add.w   d3,d1									; pair 13: advance V to cell B
        move.w  d1,d7									; pair 13: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 13: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 13: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 13: advance U to next pair
        add.w   d3,d1									; pair 13: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 13: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 13: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 13: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 13: select plane 1 byte
        move.b  d4,(a4)+								; pair 13: write plane 1 byte
        swap    d4									; pair 13: select upper plane word
        move.b  d4,(a5)+								; pair 13: write plane 2 byte
        lsr.w   #8,d4									; pair 13: select plane 3 byte
        move.b  d4,(a0)+								; pair 13: write plane 3 byte

        move.w  d1,d6									; pair 14: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 14: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 14: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 14: advance U to cell B
        add.w   d3,d1									; pair 14: advance V to cell B
        move.w  d1,d7									; pair 14: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 14: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 14: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 14: advance U to next pair
        add.w   d3,d1									; pair 14: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 14: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 14: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 14: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 14: select plane 1 byte
        move.b  d4,(a4)+								; pair 14: write plane 1 byte
        swap    d4									; pair 14: select upper plane word
        move.b  d4,(a5)+								; pair 14: write plane 2 byte
        lsr.w   #8,d4									; pair 14: select plane 3 byte
        move.b  d4,(a0)+								; pair 14: write plane 3 byte

        move.w  d1,d6									; pair 15: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 15: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 15: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 15: advance U to cell B
        add.w   d3,d1									; pair 15: advance V to cell B
        move.w  d1,d7									; pair 15: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 15: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 15: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 15: advance U to next pair
        add.w   d3,d1									; pair 15: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 15: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 15: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 15: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 15: select plane 1 byte
        move.b  d4,(a4)+								; pair 15: write plane 1 byte
        swap    d4									; pair 15: select upper plane word
        move.b  d4,(a5)+								; pair 15: write plane 2 byte
        lsr.w   #8,d4									; pair 15: select plane 3 byte
        move.b  d4,(a0)+								; pair 15: write plane 3 byte

        move.w  d1,d6									; pair 16: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 16: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 16: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 16: advance U to cell B
        add.w   d3,d1									; pair 16: advance V to cell B
        move.w  d1,d7									; pair 16: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 16: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 16: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 16: advance U to next pair
        add.w   d3,d1									; pair 16: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 16: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 16: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 16: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 16: select plane 1 byte
        move.b  d4,(a4)+								; pair 16: write plane 1 byte
        swap    d4									; pair 16: select upper plane word
        move.b  d4,(a5)+								; pair 16: write plane 2 byte
        lsr.w   #8,d4									; pair 16: select plane 3 byte
        move.b  d4,(a0)+								; pair 16: write plane 3 byte

        move.w  d1,d6									; pair 17: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 17: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 17: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 17: advance U to cell B
        add.w   d3,d1									; pair 17: advance V to cell B
        move.w  d1,d7									; pair 17: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 17: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 17: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 17: advance U to next pair
        add.w   d3,d1									; pair 17: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 17: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 17: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 17: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 17: select plane 1 byte
        move.b  d4,(a4)+								; pair 17: write plane 1 byte
        swap    d4									; pair 17: select upper plane word
        move.b  d4,(a5)+								; pair 17: write plane 2 byte
        lsr.w   #8,d4									; pair 17: select plane 3 byte
        move.b  d4,(a0)+								; pair 17: write plane 3 byte

        move.w  d1,d6									; pair 18: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 18: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 18: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 18: advance U to cell B
        add.w   d3,d1									; pair 18: advance V to cell B
        move.w  d1,d7									; pair 18: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 18: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 18: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 18: advance U to next pair
        add.w   d3,d1									; pair 18: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 18: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 18: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 18: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 18: select plane 1 byte
        move.b  d4,(a4)+								; pair 18: write plane 1 byte
        swap    d4									; pair 18: select upper plane word
        move.b  d4,(a5)+								; pair 18: write plane 2 byte
        lsr.w   #8,d4									; pair 18: select plane 3 byte
        move.b  d4,(a0)+								; pair 18: write plane 3 byte

        move.w  d1,d6									; pair 19: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 19: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 19: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 19: advance U to cell B
        add.w   d3,d1									; pair 19: advance V to cell B
        move.w  d1,d7									; pair 19: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 19: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 19: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 19: advance U to next pair
        add.w   d3,d1									; pair 19: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 19: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 19: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 19: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 19: select plane 1 byte
        move.b  d4,(a4)+								; pair 19: write plane 1 byte
        swap    d4									; pair 19: select upper plane word
        move.b  d4,(a5)+								; pair 19: write plane 2 byte
        lsr.w   #8,d4									; pair 19: select plane 3 byte
        move.b  d4,(a0)+								; pair 19: write plane 3 byte

        move.w  d1,d6									; pair 20: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 20: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 20: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 20: advance U to cell B
        add.w   d3,d1									; pair 20: advance V to cell B
        move.w  d1,d7									; pair 20: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 20: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 20: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 20: advance U to next pair
        add.w   d3,d1									; pair 20: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 20: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 20: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 20: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 20: select plane 1 byte
        move.b  d4,(a4)+								; pair 20: write plane 1 byte
        swap    d4									; pair 20: select upper plane word
        move.b  d4,(a5)+								; pair 20: write plane 2 byte
        lsr.w   #8,d4									; pair 20: select plane 3 byte
        move.b  d4,(a0)+								; pair 20: write plane 3 byte

        move.w  d1,d6									; pair 21: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 21: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 21: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 21: advance U to cell B
        add.w   d3,d1									; pair 21: advance V to cell B
        move.w  d1,d7									; pair 21: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 21: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 21: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 21: advance U to next pair
        add.w   d3,d1									; pair 21: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 21: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 21: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 21: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 21: select plane 1 byte
        move.b  d4,(a4)+								; pair 21: write plane 1 byte
        swap    d4									; pair 21: select upper plane word
        move.b  d4,(a5)+								; pair 21: write plane 2 byte
        lsr.w   #8,d4									; pair 21: select plane 3 byte
        move.b  d4,(a0)+								; pair 21: write plane 3 byte

        move.w  d1,d6									; pair 22: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 22: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 22: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 22: advance U to cell B
        add.w   d3,d1									; pair 22: advance V to cell B
        move.w  d1,d7									; pair 22: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 22: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 22: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 22: advance U to next pair
        add.w   d3,d1									; pair 22: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 22: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 22: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 22: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 22: select plane 1 byte
        move.b  d4,(a4)+								; pair 22: write plane 1 byte
        swap    d4									; pair 22: select upper plane word
        move.b  d4,(a5)+								; pair 22: write plane 2 byte
        lsr.w   #8,d4									; pair 22: select plane 3 byte
        move.b  d4,(a0)+								; pair 22: write plane 3 byte

        move.w  d1,d6									; pair 23: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 23: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 23: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 23: advance U to cell B
        add.w   d3,d1									; pair 23: advance V to cell B
        move.w  d1,d7									; pair 23: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 23: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 23: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 23: advance U to next pair
        add.w   d3,d1									; pair 23: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 23: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 23: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 23: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 23: select plane 1 byte
        move.b  d4,(a4)+								; pair 23: write plane 1 byte
        swap    d4									; pair 23: select upper plane word
        move.b  d4,(a5)+								; pair 23: write plane 2 byte
        lsr.w   #8,d4									; pair 23: select plane 3 byte
        move.b  d4,(a0)+								; pair 23: write plane 3 byte

        move.w  d1,d6									; pair 24: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 24: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 24: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 24: advance U to cell B
        add.w   d3,d1									; pair 24: advance V to cell B
        move.w  d1,d7									; pair 24: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 24: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 24: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 24: advance U to next pair
        add.w   d3,d1									; pair 24: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 24: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 24: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 24: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 24: select plane 1 byte
        move.b  d4,(a4)+								; pair 24: write plane 1 byte
        swap    d4									; pair 24: select upper plane word
        move.b  d4,(a5)+								; pair 24: write plane 2 byte
        lsr.w   #8,d4									; pair 24: select plane 3 byte
        move.b  d4,(a0)+								; pair 24: write plane 3 byte

        move.w  d1,d6									; pair 25: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 25: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 25: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 25: advance U to cell B
        add.w   d3,d1									; pair 25: advance V to cell B
        move.w  d1,d7									; pair 25: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 25: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 25: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 25: advance U to next pair
        add.w   d3,d1									; pair 25: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 25: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 25: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 25: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 25: select plane 1 byte
        move.b  d4,(a4)+								; pair 25: write plane 1 byte
        swap    d4									; pair 25: select upper plane word
        move.b  d4,(a5)+								; pair 25: write plane 2 byte
        lsr.w   #8,d4									; pair 25: select plane 3 byte
        move.b  d4,(a0)+								; pair 25: write plane 3 byte

        move.w  d1,d6									; pair 26: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 26: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 26: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 26: advance U to cell B
        add.w   d3,d1									; pair 26: advance V to cell B
        move.w  d1,d7									; pair 26: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 26: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 26: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 26: advance U to next pair
        add.w   d3,d1									; pair 26: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 26: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 26: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 26: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 26: select plane 1 byte
        move.b  d4,(a4)+								; pair 26: write plane 1 byte
        swap    d4									; pair 26: select upper plane word
        move.b  d4,(a5)+								; pair 26: write plane 2 byte
        lsr.w   #8,d4									; pair 26: select plane 3 byte
        move.b  d4,(a0)+								; pair 26: write plane 3 byte

        move.w  d1,d6									; pair 27: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 27: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 27: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 27: advance U to cell B
        add.w   d3,d1									; pair 27: advance V to cell B
        move.w  d1,d7									; pair 27: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 27: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 27: load RGB4 table offset for cell B
        add.w   d2,d0									; pair 27: advance U to next pair
        add.w   d3,d1									; pair 27: advance V to next pair
        move.l  (a6,d6.w),d4								; pair 27: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 27: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 27: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 27: select plane 1 byte
        move.b  d4,(a4)+								; pair 27: write plane 1 byte
        swap    d4									; pair 27: select upper plane word
        move.b  d4,(a5)+								; pair 27: write plane 2 byte
        lsr.w   #8,d4									; pair 27: select plane 3 byte
        move.b  d4,(a0)+								; pair 27: write plane 3 byte

        move.w  d1,d6									; pair 28: copy V for cell A
        move.b  (a2,d0.w),d6								; pair 28: merge wrapped U byte for cell A
        move.w  (a1,d6.w),d6								; pair 28: load RGB4 table offset for cell A
        add.w   d2,d0									; pair 28: advance U to cell B
        add.w   d3,d1									; pair 28: advance V to cell B
        move.w  d1,d7									; pair 28: copy V for cell B
        move.b  (a2,d0.w),d7								; pair 28: merge wrapped U byte for cell B
        move.w  (a1,d7.w),d7								; pair 28: load RGB4 table offset for cell B
        move.l  (a6,d6.w),d4								; pair 28: load four high-nibble plane bytes
        or.l    4(a6,d7.w),d4								; pair 28: merge four low-nibble plane bytes
        move.b  d4,(a3)+								; pair 28: write plane 0 byte and advance
        lsr.w   #8,d4									; pair 28: select plane 1 byte
        move.b  d4,(a4)+								; pair 28: write plane 1 byte
        swap    d4									; pair 28: select upper plane word
        move.b  d4,(a5)+								; pair 28: write plane 2 byte
        lsr.w   #8,d4									; pair 28: select plane 3 byte
        move.b  d4,(a0)+								; pair 28: write plane 3 byte
        dbra    d5,RenderHamRowsCoreDelta						; branch when another row follows
        movem.l (sp)+,d4-d7/a3-a6							; restore clobbered C registers only
        rts										; return to C
RenderHamRowsCoreDelta:									; branch target after the current row finished
        add.w   HamRowUDeltaValue(pc),d0					        ; advance U to next rendered row from data storage
        add.w   HamRowVDeltaValue(pc),d1					        ; advance V to next rendered row from data storage
        bra.w   RenderHamRowsCore							; render next row inline

        even										; keep the row-delta data word-aligned
HamRowDeltaVars:									; cache-safe row-delta storage for 68020+ instruction caches
HamRowUDeltaValue:								        ; row-to-row U advance value
        dc.w    0									; updated as data before each render band
HamRowVDeltaValue:								        ; row-to-row V advance value
        dc.w    0									; updated as data before each render band
