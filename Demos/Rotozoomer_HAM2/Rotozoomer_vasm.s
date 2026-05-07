;**********************************************************************
;* 4x4 HAM7 BPLDAT Quirk Rotozoomer ASM Renderer                       *
;*                                                                    *
;* 52x52 hybrid row cache renderer. Rows 43-51 are cached in Chip.    *
;* Rows 35-39 use a half-rate Chip cache, rows 40-42 are Slow-copied. *
;* Runtime draws rows 0-26 every frame and rows 27-34 at half rate.   *
;* BPL5DAT/BPL6DAT control words are handled by the Copperlist in C.  *
;**********************************************************************

        machine 68000

VPOSR               equ     $00DFF004 ; vertical beam position register
COP1LC              equ     $00DFF080 ; copper list 1 pointer register
HAM_CORE_DONE_LOW   equ     $B0       ; low byte after dynamic rows 0-26 are off-screen
HAM_TEMPORAL_DONE_LOW equ   $D0       ; low byte after dynamic rows 27-34 are off-screen
HAM_DYNAMIC_DONE_LOW equ    $F1       ; low byte after row-43 pointer fetch is safely past

HAM_ROWS            equ     52       ; number of displayed HAM cell rows
HAM_LIVE_ROWS       equ     27       ; number of runtime-rendered core cell rows
HAM_SLOW_ROWS       equ     3        ; number of slow-copied rows per frame
HAM_SLOW_START_ROW  equ     40       ; first slow-copied row
HAM_CACHE_ROWS      equ     9       ; number of stored cached bottom rows per frame
HAM_CACHE_START_ROW equ     43       ; first cached bottom row
HAM_COPPER_HALFRATE_BPLPTR_WORD equ 481 ; value slot for half-rate row pointers
HAM_COPPER_HALFRATE_BPLPTR_BYTES equ 962 ; byte slot for half-rate row pointers
HAM_COPPER_CACHE_BPLPTR_WORD equ 589 ; value slot for cached run pointers
HAM_COPPER_CACHE_BPLPTR_BYTES equ 1178 ; byte slot for cached run pointers
HAM_FETCH_BYTES     equ     26       ; bytes per rendered bitplane row
HAM_PLANE_BYTES     equ     1352     ; bytes per displayed HAM bitplane
HAM_DYNAMIC_PLANE_BYTES equ 988       ; bytes per compact runtime/copied dynamic bitplane
HAM_CACHE_PLANE_BYTES equ   234      ; bytes per cached compact bitplane
HAM_HALFRATE_ROWS   equ     5        ; number of half-rate rows per cached frame
HAM_TEMPORAL_ROWS    equ     8        ; number of temporal dynamic rows
HAM_TEMPORAL_START_ROW equ 27         ; first temporal dynamic row
HAM_TEMPORAL_DEST_OFFSET equ 702      ; compact row 27 byte offset in dynamic planes
HAM_TEMPORAL_PLANE_BYTES equ 208      ; bytes copied for temporal rows per plane
HAM_TEMPORAL_NEXT_PLANE_SKIP equ 780  ; advance after temporal block to next plane
HAM_HALFRATE_START_ROW equ  35       ; first half-rate cached row
HAM_HALFRATE_PLANE_BYTES equ 130      ; bytes per half-rate compact bitplane
HAM_SLOW_PLANE_BYTES equ    78       ; bytes per slow compact bitplane
HAM_SLOW_DEST_OFFSET equ    910      ; compact slow-row offset in dynamic planes
HAM_SLOW_NEXT_PLANE_SKIP equ 910      ; advance after copied block to next plane

; void WaitHamLiveDoneAndSwitchCopperAsm(a0=CopperList)

_WaitHamLiveDoneAndSwitchCopperAsm::
        btst.b  #0,VPOSR+1                ; test PAL line bit 8
        bne.s   .switch                   ; switch immediately in lower border/vblank
        cmp.b   #HAM_CORE_DONE_LOW,VPOSR+2 ; check if core rows are already off-screen
        bhs.s   .switch                   ; switch when core rows are safe to overwrite
.wait_live:
        cmp.b   #HAM_CORE_DONE_LOW,VPOSR+2 ; wait for first line below core rows
        blo.s   .wait_live                ; stay while the beam still reads core rows
.switch:
        move.l  a0,COP1LC                 ; prepare copper list for the next frame
        rts                               ; return to C

; void UpdateCopperHalfAndCachedPointerAsm(a0=CopperList, a1=CachedFrame, d1=HalfFrame)

_UpdateCopperHalfAndCachedPointerAsm::
        lea     HAM_COPPER_CACHE_BPLPTR_BYTES(a0),a0 ; get full-rate pointer value slot
        move.l  a1,d0                    ; load cached plane 0 pointer
        swap    d0                       ; select high word
        move.w  d0,(a0)                  ; write plane 0 high word
        swap    d0                       ; select low word
        move.w  d0,4(a0)                ; write plane 0 low word
        lea     HAM_CACHE_PLANE_BYTES(a1),a1 ; advance to cached plane 1
        move.l  a1,d0                    ; load cached plane 1 pointer
        swap    d0                       ; select high word
        move.w  d0,8(a0)                ; write plane 1 high word
        swap    d0                       ; select low word
        move.w  d0,12(a0)                ; write plane 1 low word
        lea     HAM_CACHE_PLANE_BYTES(a1),a1 ; advance to cached plane 2
        move.l  a1,d0                    ; load cached plane 2 pointer
        swap    d0                       ; select high word
        move.w  d0,16(a0)                ; write plane 2 high word
        swap    d0                       ; select low word
        move.w  d0,20(a0)                ; write plane 2 low word
        lea     HAM_CACHE_PLANE_BYTES(a1),a1 ; advance to cached plane 3
        move.l  a1,d0                    ; load cached plane 3 pointer
        swap    d0                       ; select high word
        move.w  d0,24(a0)                ; write plane 3 high word
        swap    d0                       ; select low word
        move.w  d0,28(a0)                ; write plane 3 low word

        movea.l d1,a1                    ; use half-rate frame pointer
        lea     HAM_COPPER_HALFRATE_BPLPTR_BYTES-HAM_COPPER_CACHE_BPLPTR_BYTES(a0),a0 ; get half-rate pointer value slot
        move.l  a1,d0                    ; load half-rate plane 0 pointer
        swap    d0                       ; select high word
        move.w  d0,(a0)                  ; write plane 0 high word
        swap    d0                       ; select low word
        move.w  d0,4(a0)                ; write plane 0 low word
        lea     HAM_HALFRATE_PLANE_BYTES(a1),a1 ; advance to half-rate plane 1
        move.l  a1,d0                    ; load half-rate plane 1 pointer
        swap    d0                       ; select high word
        move.w  d0,8(a0)                ; write plane 1 high word
        swap    d0                       ; select low word
        move.w  d0,12(a0)                ; write plane 1 low word
        lea     HAM_HALFRATE_PLANE_BYTES(a1),a1 ; advance to half-rate plane 2
        move.l  a1,d0                    ; load half-rate plane 2 pointer
        swap    d0                       ; select high word
        move.w  d0,16(a0)                ; write plane 2 high word
        swap    d0                       ; select low word
        move.w  d0,20(a0)                ; write plane 2 low word
        lea     HAM_HALFRATE_PLANE_BYTES(a1),a1 ; advance to half-rate plane 3
        move.l  a1,d0                    ; load half-rate plane 3 pointer
        swap    d0                       ; select high word
        move.w  d0,24(a0)                ; write plane 3 high word
        swap    d0                       ; select low word
        move.w  d0,28(a0)                ; write plane 3 low word
        rts                              ; return to C

; void CopyHamSlowRowsAndUpdateCopperAsm(a0=DynamicFrame, a1=SlowRows, a2=CopperList, a3=CachedFrame, d0=HalfFrame)
_CopyHamSlowRowsAndUpdateCopperAsm::
        move.l  a0,-(sp)                 ; save dynamic frame pointer for the slow copy
        move.l  a1,-(sp)                 ; save slow row source pointer for the slow copy
        movea.l a2,a0                    ; use copper list pointer for early pointer patching
        movea.l a3,a1                    ; use full-rate cached frame pointer for early patching
        move.l  d0,d1                    ; keep half-rate frame pointer for the patcher
        bsr.w   _UpdateCopperHalfAndCachedPointerAsm ; patch inactive copper list while beam catches up
        movea.l (sp)+,a1                 ; restore slow row source pointer
        movea.l (sp)+,a0                 ; restore dynamic frame pointer
        btst.b  #0,VPOSR+1                ; test PAL line bit 8 before touching dynamic slow rows
        bne.s   .dynamic_safe             ; copying is safe in lower border/vblank
        move.b  VPOSR+2,d1                ; read current low vertical beam byte
        cmp.b   #HAM_CORE_DONE_LOW,d1     ; detect wrap into the next frame
        blo.s   .dynamic_safe             ; copying is safe after the old frame wrapped away
        cmp.b   #HAM_DYNAMIC_DONE_LOW,d1  ; check if slow rows are already off-screen
        bhs.s   .dynamic_safe             ; copy immediately if dynamic rows are safe
.wait_dynamic:
        cmp.b   #HAM_DYNAMIC_DONE_LOW,VPOSR+2 ; wait for first line below slow rows
        blo.s   .wait_dynamic             ; stay while the beam still reads slow rows
.dynamic_safe:
        movem.l d2-d7/a2-a5,-(sp)        ; save copy registers
        lea     HAM_SLOW_DEST_OFFSET(a0),a0 ; get compact slow rows in plane 0

        movem.l (a1)+,d0-d7/a2-a5        ; plane 0: read first 48 bytes
        movem.l d0-d7/a2-a5,(a0)         ; plane 0: write first 48 bytes
        lea     48(a0),a0                ; plane 0: advance to second block
        movem.l (a1)+,d0-d6              ; plane 0: read next 28 bytes
        movem.l d0-d6,(a0)               ; plane 0: write next 28 bytes
        lea     28(a0),a0                ; plane 0: advance to final word
        move.w  (a1)+,(a0)+              ; plane 0: copy final 2 bytes
        lea     HAM_SLOW_NEXT_PLANE_SKIP(a0),a0 ; advance to plane 1 slow rows

        movem.l (a1)+,d0-d7/a2-a5        ; plane 1: read first 48 bytes
        movem.l d0-d7/a2-a5,(a0)         ; plane 1: write first 48 bytes
        lea     48(a0),a0                ; plane 1: advance to second block
        movem.l (a1)+,d0-d6              ; plane 1: read next 28 bytes
        movem.l d0-d6,(a0)               ; plane 1: write next 28 bytes
        lea     28(a0),a0                ; plane 1: advance to final word
        move.w  (a1)+,(a0)+              ; plane 1: copy final 2 bytes
        lea     HAM_SLOW_NEXT_PLANE_SKIP(a0),a0 ; advance to plane 2 slow rows

        movem.l (a1)+,d0-d7/a2-a5        ; plane 2: read first 48 bytes
        movem.l d0-d7/a2-a5,(a0)         ; plane 2: write first 48 bytes
        lea     48(a0),a0                ; plane 2: advance to second block
        movem.l (a1)+,d0-d6              ; plane 2: read next 28 bytes
        movem.l d0-d6,(a0)               ; plane 2: write next 28 bytes
        lea     28(a0),a0                ; plane 2: advance to final word
        move.w  (a1)+,(a0)+              ; plane 2: copy final 2 bytes
        lea     HAM_SLOW_NEXT_PLANE_SKIP(a0),a0 ; advance to plane 3 slow rows

        movem.l (a1)+,d0-d7/a2-a5        ; plane 3: read first 48 bytes
        movem.l d0-d7/a2-a5,(a0)         ; plane 3: write first 48 bytes
        lea     48(a0),a0                ; plane 3: advance to second block
        movem.l (a1)+,d0-d6              ; plane 3: read next 28 bytes
        movem.l d0-d6,(a0)               ; plane 3: write next 28 bytes
        lea     28(a0),a0                ; plane 3: advance to final word
        move.w  (a1)+,(a0)+              ; plane 3: copy final 2 bytes

        movem.l (sp)+,d2-d7/a2-a5        ; restore copy registers
        rts                              ; return after the slow rows are copied

; void CopyHamTemporalRowsAsm(a0=TargetDynamicFrame, a1=SourceDynamicFrame)
_CopyHamTemporalRowsAsm::
        btst.b  #0,VPOSR+1                ; test PAL line bit 8 before touching temporal rows
        bne.s   .temporal_copy_safe       ; copying is safe in lower border/vblank
        cmp.b   #HAM_TEMPORAL_DONE_LOW,VPOSR+2 ; check if temporal rows are already off-screen
        bhs.s   .temporal_copy_safe       ; copy immediately when rows 27-34 are safe
.wait_temporal_copy:
        cmp.b   #HAM_TEMPORAL_DONE_LOW,VPOSR+2 ; wait for first line below temporal rows
        blo.s   .wait_temporal_copy       ; stay while the beam still reads temporal rows
.temporal_copy_safe:
        movem.l d2-d7/a2-a6,-(sp)        ; save registers used by the block copy
        lea     HAM_TEMPORAL_DEST_OFFSET(a0),a0 ; get target temporal row block in plane 0
        lea     HAM_TEMPORAL_DEST_OFFSET(a1),a1 ; get source temporal row block in plane 0

        movem.l (a1)+,d0-d7/a2-a6        ; plane 0: read first 52-byte block
        movem.l d0-d7/a2-a6,(a0)         ; plane 0: write first 52-byte block
        lea     52(a0),a0                ; plane 0: advance to next block
        movem.l (a1)+,d0-d7/a2-a6        ; plane 0: read second 52-byte block
        movem.l d0-d7/a2-a6,(a0)         ; plane 0: write second 52-byte block
        lea     52(a0),a0                ; plane 0: advance to next block
        movem.l (a1)+,d0-d7/a2-a6        ; plane 0: read third 52-byte block
        movem.l d0-d7/a2-a6,(a0)         ; plane 0: write third 52-byte block
        lea     52(a0),a0                ; plane 0: advance to next block
        movem.l (a1)+,d0-d7/a2-a6        ; plane 0: read fourth 52-byte block
        movem.l d0-d7/a2-a6,(a0)         ; plane 0: write fourth 52-byte block
        lea     52(a0),a0                ; plane 0: advance past copied rows
        lea     HAM_TEMPORAL_NEXT_PLANE_SKIP(a0),a0 ; advance to plane 1 temporal rows
        lea     HAM_TEMPORAL_NEXT_PLANE_SKIP(a1),a1 ; advance source to plane 1 temporal rows

        movem.l (a1)+,d0-d7/a2-a6        ; plane 1: read first 52-byte block
        movem.l d0-d7/a2-a6,(a0)         ; plane 1: write first 52-byte block
        lea     52(a0),a0                ; plane 1: advance to next block
        movem.l (a1)+,d0-d7/a2-a6        ; plane 1: read second 52-byte block
        movem.l d0-d7/a2-a6,(a0)         ; plane 1: write second 52-byte block
        lea     52(a0),a0                ; plane 1: advance to next block
        movem.l (a1)+,d0-d7/a2-a6        ; plane 1: read third 52-byte block
        movem.l d0-d7/a2-a6,(a0)         ; plane 1: write third 52-byte block
        lea     52(a0),a0                ; plane 1: advance to next block
        movem.l (a1)+,d0-d7/a2-a6        ; plane 1: read fourth 52-byte block
        movem.l d0-d7/a2-a6,(a0)         ; plane 1: write fourth 52-byte block
        lea     52(a0),a0                ; plane 1: advance past copied rows
        lea     HAM_TEMPORAL_NEXT_PLANE_SKIP(a0),a0 ; advance to plane 2 temporal rows
        lea     HAM_TEMPORAL_NEXT_PLANE_SKIP(a1),a1 ; advance source to plane 2 temporal rows

        movem.l (a1)+,d0-d7/a2-a6        ; plane 2: read first 52-byte block
        movem.l d0-d7/a2-a6,(a0)         ; plane 2: write first 52-byte block
        lea     52(a0),a0                ; plane 2: advance to next block
        movem.l (a1)+,d0-d7/a2-a6        ; plane 2: read second 52-byte block
        movem.l d0-d7/a2-a6,(a0)         ; plane 2: write second 52-byte block
        lea     52(a0),a0                ; plane 2: advance to next block
        movem.l (a1)+,d0-d7/a2-a6        ; plane 2: read third 52-byte block
        movem.l d0-d7/a2-a6,(a0)         ; plane 2: write third 52-byte block
        lea     52(a0),a0                ; plane 2: advance to next block
        movem.l (a1)+,d0-d7/a2-a6        ; plane 2: read fourth 52-byte block
        movem.l d0-d7/a2-a6,(a0)         ; plane 2: write fourth 52-byte block
        lea     52(a0),a0                ; plane 2: advance past copied rows
        lea     HAM_TEMPORAL_NEXT_PLANE_SKIP(a0),a0 ; advance to plane 3 temporal rows
        lea     HAM_TEMPORAL_NEXT_PLANE_SKIP(a1),a1 ; advance source to plane 3 temporal rows

        movem.l (a1)+,d0-d7/a2-a6        ; plane 3: read first 52-byte block
        movem.l d0-d7/a2-a6,(a0)         ; plane 3: write first 52-byte block
        lea     52(a0),a0                ; plane 3: advance to next block
        movem.l (a1)+,d0-d7/a2-a6        ; plane 3: read second 52-byte block
        movem.l d0-d7/a2-a6,(a0)         ; plane 3: write second 52-byte block
        lea     52(a0),a0                ; plane 3: advance to next block
        movem.l (a1)+,d0-d7/a2-a6        ; plane 3: read third 52-byte block
        movem.l d0-d7/a2-a6,(a0)         ; plane 3: write third 52-byte block
        lea     52(a0),a0                ; plane 3: advance to next block
        movem.l (a1)+,d0-d7/a2-a6        ; plane 3: read fourth 52-byte block
        movem.l d0-d7/a2-a6,(a0)         ; plane 3: write fourth 52-byte block
        lea     52(a0),a0                ; plane 3: advance past copied rows
        movem.l (sp)+,d2-d7/a2-a6        ; restore registers used by the block copy
        rts                              ; return to C
; void RenderHamTemporalRowsAsm(a0=Base, a1=TextureCellsMid, a2=UOffsetTableMid,
;                               a3=PairTables, d0=DuDx, d1=DvDx,
;                               d4=RowU, d5=RowV)

_RenderHamTemporalRowsAsm::
        btst.b  #0,VPOSR+1                ; test PAL line bit 8 before touching temporal rows
        bne.s   .temporal_render_safe     ; rendering is safe in lower border/vblank
        cmp.b   #HAM_TEMPORAL_DONE_LOW,VPOSR+2 ; check if temporal rows are already off-screen
        bhs.s   .temporal_render_safe     ; render immediately when rows 27-34 are safe
.wait_temporal_render:
        cmp.b   #HAM_TEMPORAL_DONE_LOW,VPOSR+2 ; wait for first line below temporal rows
        blo.s   .wait_temporal_render     ; stay while the beam still reads temporal rows
.temporal_render_safe:
        movem.l d2-d7/a3-a6,-(sp)        ; save used C registers

        move.w  d0,d2                    ; d2 = horizontal U step
        move.w  d1,d3                    ; d3 = horizontal V step
        move.w  d4,d0                    ; d0 = row 0 U
        move.w  d5,d1                    ; d1 = row 0 V
        movea.l a3,a6                    ; a6 = interleaved pair table base

        move.w  d3,d6                    ; build temporal start U offset from DvDx
        lsl.w   #5,d6                    ; d6 = DvDx * 32
        move.w  d3,d7                    ; d7 = DvDx
        lsl.w   #2,d7                    ; d7 = DvDx * 4
        sub.w   d7,d6                    ; d6 = DvDx * 28
        sub.w   d3,d6                    ; d6 = DvDx * 27
        sub.w   d6,d0                    ; start U at temporal row 27

        move.w  d2,d6                    ; build temporal start V offset from DuDx
        lsl.w   #5,d6                    ; d6 = DuDx * 32
        move.w  d2,d7                    ; d7 = DuDx
        lsl.w   #2,d7                    ; d7 = DuDx * 4
        sub.w   d7,d6                    ; d6 = DuDx * 28
        sub.w   d2,d6                    ; d6 = DuDx * 27
        add.w   d6,d1                    ; start V at temporal row 27

        move.w  d2,d6                    ; build temporal U delta from DuDx
        lsl.w   #4,d6                    ; d6 = DuDx * 16
        move.w  d6,d7                    ; d7 = DuDx * 16
        add.w   d6,d6                    ; d6 = DuDx * 32
        add.w   d7,d6                    ; d6 = DuDx * 48
        move.w  d2,d7                    ; d7 = DuDx
        lsl.w   #2,d7                    ; d7 = DuDx * 4
        add.w   d7,d6                    ; d6 = DuDx * 52
        neg.w   d6                       ; d6 = -DuDx * 52
        sub.w   d3,d6                    ; d6 = -DuDx * 52 - DvDx
        add.w   d2,d6                    ; d6 = -DuDx * 51 - DvDx
        lea     TemporalRowUDelta+2(pc),a5 ; get temporal U delta immediate
        move.w  d6,(a5)                  ; patch temporal U delta

        move.w  d3,d6                    ; build temporal V delta from DvDx
        lsl.w   #4,d6                    ; d6 = DvDx * 16
        move.w  d6,d7                    ; d7 = DvDx * 16
        add.w   d6,d6                    ; d6 = DvDx * 32
        add.w   d7,d6                    ; d6 = DvDx * 48
        move.w  d3,d7                    ; d7 = DvDx
        lsl.w   #2,d7                    ; d7 = DvDx * 4
        add.w   d7,d6                    ; d6 = DvDx * 52
        neg.w   d6                       ; d6 = -DvDx * 52
        add.w   d2,d6                    ; d6 = -DvDx * 52 + DuDx
        add.w   d3,d6                    ; d6 = -DvDx * 51 + DuDx
        lea     TemporalRowVDelta+2(pc),a5 ; get temporal V delta immediate
        move.w  d6,(a5)                  ; patch temporal V delta

        moveq   #HAM_TEMPORAL_ROWS-2,d5  ; d5 = temporal row transition counter
        lea     HAM_TEMPORAL_DEST_OFFSET(a0),a3 ; a3 = temporal plane 0 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a3),a4 ; a4 = temporal plane 1 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a4),a5 ; a5 = temporal plane 2 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a5),a0 ; a0 = temporal plane 3 write pointer
TemporalRowLoop:
        bsr.w   RenderHamSharedRow        ; render temporal row and leave d0/d1 at row end
TemporalRowUDelta:
        add.w   #0,d0                    ; advance U to next temporal row
TemporalRowVDelta:
        add.w   #0,d1                    ; advance V to next temporal row
        dbra    d5,TemporalRowLoop       ; render next temporal row with transition
        bsr.w   RenderHamSharedRow        ; render final temporal row without unused delta

        movem.l (sp)+,d2-d7/a3-a6        ; restore used C registers
        rts                              ; return to C

; void RenderHamLiveRowsAsm(a0=Base, a1=TextureCellsMid, a2=UOffsetTableMid,
;                             a3=PairTables, d0=DuDx, d1=DvDx,
;                             d4=RowU, d5=RowV)

_RenderHamLiveRowsAsm::
        movem.l d2-d7/a3-a6,-(sp)        ; save used C registers

        move.w  d0,d2                    ; d2 = horizontal U step
        move.w  d1,d3                    ; d3 = horizontal V step
        move.w  d4,d0                    ; d0 = row 0 U
        move.w  d5,d1                    ; d1 = row 0 V
        movea.l a3,a6                    ; a6 = interleaved pair table base

        move.w  d2,d6                    ; build Live U delta from DuDx
        lsl.w   #4,d6                    ; d6 = DuDx * 16
        move.w  d6,d7                    ; d7 = DuDx * 16
        add.w   d6,d6                    ; d6 = DuDx * 32
        add.w   d7,d6                    ; d6 = DuDx * 48
        move.w  d2,d7                    ; d7 = DuDx
        lsl.w   #2,d7                    ; d7 = DuDx * 4
        add.w   d7,d6                    ; d6 = DuDx * 52
        neg.w   d6                       ; d6 = -DuDx * 52
        sub.w   d3,d6                    ; d6 = -DuDx * 52 - DvDx
        add.w   d2,d6                    ; d6 = -DuDx * 51 - DvDx
        lea     LiveRowUDelta+2(pc),a5 ; get live U delta immediate
        move.w  d6,(a5)                  ; patch live U delta

        move.w  d3,d6                    ; build Live V delta from DvDx
        lsl.w   #4,d6                    ; d6 = DvDx * 16
        move.w  d6,d7                    ; d7 = DvDx * 16
        add.w   d6,d6                    ; d6 = DvDx * 32
        add.w   d7,d6                    ; d6 = DvDx * 48
        move.w  d3,d7                    ; d7 = DvDx
        lsl.w   #2,d7                    ; d7 = DvDx * 4
        add.w   d7,d6                    ; d6 = DvDx * 52
        neg.w   d6                       ; d6 = -DvDx * 52
        add.w   d2,d6                    ; d6 = -DvDx * 52 + DuDx
        add.w   d3,d6                    ; d6 = -DvDx * 51 + DuDx
        lea     LiveRowVDelta+2(pc),a5 ; get live V delta immediate
        move.w  d6,(a5)                  ; patch live V delta

        moveq   #HAM_LIVE_ROWS-1,d5      ; d5 = live row counter
        movea.l a0,a3                    ; a3 = live plane 0 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a3),a4 ; a4 = live plane 1 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a4),a5 ; a5 = live plane 2 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a5),a0 ; a0 = live plane 3 write pointer
LiveRowLoop:
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

LiveRowUDelta:
        add.w   #0,d0                    ; advance U to next live row
LiveRowVDelta:
        add.w   #0,d1                    ; advance V to next live row
        dbra    d5,LiveRowLoop           ; render all live rows inline

        movem.l (sp)+,d2-d7/a3-a6        ; restore used C registers
        rts                              ; return to C

; void RenderHamHalfRowsAsm(a0=Base, a1=TextureCellsMid, a2=UOffsetTableMid,
;                             a3=PairTables, d0=DuDx, d1=DvDx,
;                             d4=RowU, d5=RowV)

_RenderHamHalfRowsAsm::
        movem.l d2-d7/a3-a6,-(sp)        ; save used C registers

        move.w  d0,d2                    ; d2 = horizontal U step
        move.w  d1,d3                    ; d3 = horizontal V step
        move.w  d4,d0                    ; d0 = row 0 U
        move.w  d5,d1                    ; d1 = row 0 V
        movea.l a3,a6                    ; a6 = interleaved pair table base

        move.w  d3,d6                    ; build half-rate start U offset from DvDx
        lsl.w   #5,d6                    ; d6 = DvDx * 32
        move.w  d3,d7                    ; d7 = DvDx
        add.w   d7,d7                    ; d7 = DvDx * 2
        add.w   d7,d6                    ; d6 = DvDx * 34
        add.w   d3,d6                    ; d6 = DvDx * 35
        sub.w   d6,d0                    ; start U at half-rate row 35

        move.w  d2,d6                    ; build half-rate start V offset from DuDx
        lsl.w   #5,d6                    ; d6 = DuDx * 32
        move.w  d2,d7                    ; d7 = DuDx
        add.w   d7,d7                    ; d7 = DuDx * 2
        add.w   d7,d6                    ; d6 = DuDx * 34
        add.w   d2,d6                    ; d6 = DuDx * 35
        add.w   d6,d1                    ; start V at half-rate row 35

        move.w  d2,d6                    ; build Half-rate U delta from DuDx
        lsl.w   #4,d6                    ; d6 = DuDx * 16
        move.w  d6,d7                    ; d7 = DuDx * 16
        add.w   d6,d6                    ; d6 = DuDx * 32
        add.w   d7,d6                    ; d6 = DuDx * 48
        move.w  d2,d7                    ; d7 = DuDx
        lsl.w   #2,d7                    ; d7 = DuDx * 4
        add.w   d7,d6                    ; d6 = DuDx * 52
        neg.w   d6                       ; d6 = -DuDx * 52
        sub.w   d3,d6                    ; d6 = -DuDx * 52 - DvDx
        add.w   d2,d6                    ; d6 = -DuDx * 51 - DvDx
        lea     HalfRowUDelta+2(pc),a5 ; get half-rate U delta immediate
        move.w  d6,(a5)                  ; patch half-rate U delta

        move.w  d3,d6                    ; build Half-rate V delta from DvDx
        lsl.w   #4,d6                    ; d6 = DvDx * 16
        move.w  d6,d7                    ; d7 = DvDx * 16
        add.w   d6,d6                    ; d6 = DvDx * 32
        add.w   d7,d6                    ; d6 = DvDx * 48
        move.w  d3,d7                    ; d7 = DvDx
        lsl.w   #2,d7                    ; d7 = DvDx * 4
        add.w   d7,d6                    ; d6 = DvDx * 52
        neg.w   d6                       ; d6 = -DvDx * 52
        add.w   d2,d6                    ; d6 = -DvDx * 52 + DuDx
        add.w   d3,d6                    ; d6 = -DvDx * 51 + DuDx
        lea     HalfRowVDelta+2(pc),a5 ; get half-rate V delta immediate
        move.w  d6,(a5)                  ; patch half-rate V delta

        moveq   #HAM_HALFRATE_ROWS-2,d5 ; d5 = half-rate row transition counter
        movea.l a0,a3                    ; a3 = half-rate plane 0 write pointer
        lea     HAM_HALFRATE_PLANE_BYTES(a3),a4      ; a4 = half-rate plane 1 write pointer
        lea     HAM_HALFRATE_PLANE_BYTES(a4),a5      ; a5 = half-rate plane 2 write pointer
        lea     HAM_HALFRATE_PLANE_BYTES(a5),a0      ; a0 = half-rate plane 3 write pointer
HalfRowLoop:
        bsr.w   RenderHamSharedRow        ; render half-rate row and leave d0/d1 at row end
HalfRowUDelta:
        add.w   #0,d0                    ; advance U to next half-rate row
HalfRowVDelta:
        add.w   #0,d1                    ; advance V to next half-rate row
        dbra    d5,HalfRowLoop          ; render next half-rate row with transition
        bsr.w   RenderHamSharedRow        ; render final half-rate row without unused delta

        movem.l (sp)+,d2-d7/a3-a6        ; restore used C registers
        rts                              ; return to C

; void RenderHamSlowRowsAsm(a0=Base, a1=TextureCellsMid, a2=UOffsetTableMid,
;                             a3=PairTables, d0=DuDx, d1=DvDx,
;                             d4=RowU, d5=RowV)

_RenderHamSlowRowsAsm::
        movem.l d2-d7/a3-a6,-(sp)        ; save used C registers

        move.w  d0,d2                    ; d2 = horizontal U step
        move.w  d1,d3                    ; d3 = horizontal V step
        move.w  d4,d0                    ; d0 = row 0 U
        move.w  d5,d1                    ; d1 = row 0 V
        movea.l a3,a6                    ; a6 = interleaved pair table base

        move.w  d3,d6                    ; build slow-copy start U offset from DvDx
        lsl.w   #5,d6                    ; d6 = DvDx * 32
        move.w  d3,d7                    ; d7 = DvDx
        lsl.w   #3,d7                    ; d7 = DvDx * 8
        add.w   d7,d6                    ; d6 = DvDx * 40
        sub.w   d6,d0                    ; start U at slow-copy row 40

        move.w  d2,d6                    ; build slow-copy start V offset from DuDx
        lsl.w   #5,d6                    ; d6 = DuDx * 32
        move.w  d2,d7                    ; d7 = DuDx
        lsl.w   #3,d7                    ; d7 = DuDx * 8
        add.w   d7,d6                    ; d6 = DuDx * 40
        add.w   d6,d1                    ; start V at slow-copy row 40

        move.w  d2,d6                    ; build Slow U delta from DuDx
        lsl.w   #4,d6                    ; d6 = DuDx * 16
        move.w  d6,d7                    ; d7 = DuDx * 16
        add.w   d6,d6                    ; d6 = DuDx * 32
        add.w   d7,d6                    ; d6 = DuDx * 48
        move.w  d2,d7                    ; d7 = DuDx
        lsl.w   #2,d7                    ; d7 = DuDx * 4
        add.w   d7,d6                    ; d6 = DuDx * 52
        neg.w   d6                       ; d6 = -DuDx * 52
        sub.w   d3,d6                    ; d6 = -DuDx * 52 - DvDx
        add.w   d2,d6                    ; d6 = -DuDx * 51 - DvDx
        lea     SlowRowUDelta+2(pc),a5 ; get slow U delta immediate
        move.w  d6,(a5)                  ; patch slow U delta

        move.w  d3,d6                    ; build Slow V delta from DvDx
        lsl.w   #4,d6                    ; d6 = DvDx * 16
        move.w  d6,d7                    ; d7 = DvDx * 16
        add.w   d6,d6                    ; d6 = DvDx * 32
        add.w   d7,d6                    ; d6 = DvDx * 48
        move.w  d3,d7                    ; d7 = DvDx
        lsl.w   #2,d7                    ; d7 = DvDx * 4
        add.w   d7,d6                    ; d6 = DvDx * 52
        neg.w   d6                       ; d6 = -DvDx * 52
        add.w   d2,d6                    ; d6 = -DvDx * 52 + DuDx
        add.w   d3,d6                    ; d6 = -DvDx * 51 + DuDx
        lea     SlowRowVDelta+2(pc),a5 ; get slow V delta immediate
        move.w  d6,(a5)                  ; patch slow V delta

        moveq   #3-2,d5             ; d5 = slow row transition counter
        movea.l a0,a3                    ; a3 = slow plane 0 write pointer
        lea     HAM_SLOW_PLANE_BYTES(a3),a4      ; a4 = slow plane 1 write pointer
        lea     HAM_SLOW_PLANE_BYTES(a4),a5      ; a5 = slow plane 2 write pointer
        lea     HAM_SLOW_PLANE_BYTES(a5),a0      ; a0 = slow plane 3 write pointer
SlowRowLoop:
        bsr.w   RenderHamSharedRow        ; render slow row and leave d0/d1 at row end
SlowRowUDelta:
        add.w   #0,d0                    ; advance U to next slow row
SlowRowVDelta:
        add.w   #0,d1                    ; advance V to next slow row
        dbra    d5,SlowRowLoop          ; render next slow row with transition
        bsr.w   RenderHamSharedRow        ; render final slow row without unused delta

        movem.l (sp)+,d2-d7/a3-a6        ; restore used C registers
        rts                              ; return to C

; void RenderHamCachedRowsAsm(a0=Base, a1=TextureCellsMid, a2=UOffsetTableMid,
;                             a3=PairTables, d0=DuDx, d1=DvDx,
;                             d4=RowU, d5=RowV)

_RenderHamCachedRowsAsm::
        movem.l d2-d7/a3-a6,-(sp)        ; save used C registers

        move.w  d0,d2                    ; d2 = horizontal U step
        move.w  d1,d3                    ; d3 = horizontal V step
        move.w  d4,d0                    ; d0 = row 0 U
        move.w  d5,d1                    ; d1 = row 0 V
        movea.l a3,a6                    ; a6 = interleaved pair table base

        move.w  d3,d6                    ; build cached start U offset from DvDx
        lsl.w   #5,d6                    ; d6 = DvDx * 32
        move.w  d3,d7                    ; d7 = DvDx
        lsl.w   #3,d7                    ; d7 = DvDx * 8
        add.w   d7,d6                    ; d6 = DvDx * 40
        move.w  d3,d7                    ; d7 = DvDx
        add.w   d7,d7                    ; d7 = DvDx * 2
        add.w   d7,d6                    ; d6 = DvDx * 42
        add.w   d3,d6                    ; d6 = DvDx * 43
        sub.w   d6,d0                    ; start U at cached row 43

        move.w  d2,d6                    ; build cached start V offset from DuDx
        lsl.w   #5,d6                    ; d6 = DuDx * 32
        move.w  d2,d7                    ; d7 = DuDx
        lsl.w   #3,d7                    ; d7 = DuDx * 8
        add.w   d7,d6                    ; d6 = DuDx * 40
        move.w  d2,d7                    ; d7 = DuDx
        add.w   d7,d7                    ; d7 = DuDx * 2
        add.w   d7,d6                    ; d6 = DuDx * 42
        add.w   d2,d6                    ; d6 = DuDx * 43
        add.w   d6,d1                    ; start V at cached row 43

        move.w  d2,d6                    ; build Cached U delta from DuDx
        lsl.w   #4,d6                    ; d6 = DuDx * 16
        move.w  d6,d7                    ; d7 = DuDx * 16
        add.w   d6,d6                    ; d6 = DuDx * 32
        add.w   d7,d6                    ; d6 = DuDx * 48
        move.w  d2,d7                    ; d7 = DuDx
        lsl.w   #2,d7                    ; d7 = DuDx * 4
        add.w   d7,d6                    ; d6 = DuDx * 52
        neg.w   d6                       ; d6 = -DuDx * 52
        sub.w   d3,d6                    ; d6 = -DuDx * 52 - DvDx
        add.w   d2,d6                    ; d6 = -DuDx * 51 - DvDx
        lea     CachedRowUDelta+2(pc),a5 ; get cached U delta immediate
        move.w  d6,(a5)                  ; patch cached U delta

        move.w  d3,d6                    ; build Cached V delta from DvDx
        lsl.w   #4,d6                    ; d6 = DvDx * 16
        move.w  d6,d7                    ; d7 = DvDx * 16
        add.w   d6,d6                    ; d6 = DvDx * 32
        add.w   d7,d6                    ; d6 = DvDx * 48
        move.w  d3,d7                    ; d7 = DvDx
        lsl.w   #2,d7                    ; d7 = DvDx * 4
        add.w   d7,d6                    ; d6 = DvDx * 52
        neg.w   d6                       ; d6 = -DvDx * 52
        add.w   d2,d6                    ; d6 = -DvDx * 52 + DuDx
        add.w   d3,d6                    ; d6 = -DvDx * 51 + DuDx
        lea     CachedRowVDelta+2(pc),a5 ; get cached V delta immediate
        move.w  d6,(a5)                  ; patch cached V delta

        moveq   #HAM_CACHE_ROWS-2,d5 ; d5 = cached row transition counter
        movea.l a0,a3                    ; a3 = cached plane 0 write pointer
        lea     HAM_CACHE_PLANE_BYTES(a3),a4      ; a4 = cached plane 1 write pointer
        lea     HAM_CACHE_PLANE_BYTES(a4),a5      ; a5 = cached plane 2 write pointer
        lea     HAM_CACHE_PLANE_BYTES(a5),a0      ; a0 = cached plane 3 write pointer
CachedRowLoop:
        bsr.w   RenderHamSharedRow        ; render cached row and leave d0/d1 at row end
CachedRowUDelta:
        add.w   #0,d0                    ; advance U to next cached row
CachedRowVDelta:
        add.w   #0,d1                    ; advance V to next cached row
        dbra    d5,CachedRowLoop          ; render next cached row with transition
        bsr.w   RenderHamSharedRow        ; render final cached row without unused delta

        movem.l (sp)+,d2-d7/a3-a6        ; restore used C registers
        rts                              ; return to C

; Shared one-row renderer. It leaves d0/d1 at the last cell of the row.

RenderHamSharedRow:
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

        rts                               ; return to caller

