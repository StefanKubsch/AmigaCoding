;**********************************************************************
;* 4x4 HAM7 BPLDAT Quirk Rotozoomer ASM Renderer                       *
;*                                                                    *
;* 52x52 hybrid row cache renderer. Rows 26-48 are cached at half-rate.    *
;* Rows 49-51 are Slow-copied; runtime draws rows 0-1 and splits 2-25. *
;* No full-rate bottom cache is used in this version.        *
;* BPL5DAT/BPL6DAT control words are handled by the Copperlist in C.  *
;**********************************************************************

        machine 68000

VPOSR               equ     $00DFF004 ; vertical beam position register
COP1LC              equ     $00DFF080 ; copper list 1 pointer register
HAM_CORE_DONE_LOW   equ     $4C       ; low byte after dynamic rows 0-1 are off-screen
HAM_TEMPORAL_UPPER_DONE_LOW equ $7C    ; low byte after temporal rows 2-13 are off-screen
HAM_TEMPORAL_DONE_LOW equ   $AC       ; low byte after temporal rows 2-25 are off-screen
HAM_DYNAMIC_DONE_LOW equ    $14       ; low byte after slow rows 49-51 are safely past

HAM_ROWS            equ     52       ; number of displayed HAM cell rows
HAM_LIVE_ROWS       equ     2       ; number of runtime-rendered core cell rows
HAM_SLOW_ROWS       equ     3        ; number of slow-copied rows per frame
HAM_SLOW_START_ROW  equ     49       ; first slow-copied row
HAM_CACHE_ROWS      equ     0       ; no full-rate cached bottom rows
HAM_CACHE_START_ROW equ     52       ; cache run disabled after display area
HAM_COPPER_HALFRATE_BPLPTR_WORD equ 373 ; value slot for half-rate row pointers
HAM_COPPER_HALFRATE_BPLPTR_BYTES equ 746 ; byte slot for half-rate row pointers
HAM_COPPER_CACHE_BPLPTR_WORD equ 0 ; full-rate cache pointer slot unused
HAM_COPPER_CACHE_BPLPTR_BYTES equ 0 ; full-rate cache pointer slot unused
HAM_FETCH_BYTES     equ     26       ; bytes per rendered bitplane row
HAM_PLANE_BYTES     equ     1352     ; bytes per displayed HAM bitplane
HAM_DYNAMIC_PLANE_BYTES equ 754       ; bytes per compact runtime/copied dynamic bitplane
HAM_CACHE_PLANE_BYTES equ   0        ; full-rate cache removed
HAM_HALFRATE_ROWS   equ     23        ; number of half-rate rows per cached frame
HAM_TEMPORAL_ROWS    equ     24       ; number of temporal dynamic rows
HAM_TEMPORAL_HALF_ROWS equ     12       ; number of rows in one temporal half
HAM_TEMPORAL_START_ROW equ 2         ; first temporal dynamic row
HAM_TEMPORAL_UPPER_DEST_OFFSET equ 52 ; compact row 2 byte offset in dynamic planes
HAM_TEMPORAL_LOWER_DEST_OFFSET equ 364 ; compact row 14 byte offset in dynamic planes
HAM_TEMPORAL_HALF_PLANE_BYTES equ 312 ; bytes copied for one temporal half per plane
HAM_TEMPORAL_HALF_NEXT_PLANE_SKIP equ 442 ; advance source after temporal half to next plane
HAM_TEMPORAL_HALF_TARGET_PLANE_SKIP equ 494 ; advance target after final temporal block to next plane
HAM_HALFRATE_START_ROW equ  26       ; first half-rate cached row
HAM_HALFRATE_PLANE_BYTES equ 598      ; bytes per half-rate compact bitplane
HAM_SLOW_PLANE_BYTES equ    78       ; bytes per slow compact bitplane
HAM_SLOW_DEST_OFFSET equ    676      ; compact slow-row offset in dynamic planes
HAM_SLOW_NEXT_PLANE_SKIP equ 676      ; advance after copied block to next plane

CUSTOMREGS          equ     $00DFF000 ; custom chip register base
BLTCON0             equ     $00DFF040 ; blitter control register 0
BLTCON1             equ     $00DFF042 ; blitter control register 1
BLTAFWM             equ     $00DFF044 ; blitter first word mask for source A
BLTALWM             equ     $00DFF046 ; blitter last word mask for source A
BLTAPTH             equ     $00DFF050 ; blitter source A pointer high
BLTAPTL             equ     $00DFF052 ; blitter source A pointer low
BLTDPTH             equ     $00DFF054 ; blitter destination D pointer high
BLTDPTL             equ     $00DFF056 ; blitter destination D pointer low
BLTSIZE             equ     $00DFF058 ; blitter start and size
BLTAMOD             equ     $00DFF064 ; blitter modulo for source A
BLTDMOD             equ     $00DFF066 ; blitter modulo for destination D
DMACONR             equ     $00DFF002 ; DMA control read
DMAB_BLITTER        equ     6         ; bit 6 of DMACONR high byte: 1=busy, 0=idle
BLTCON0_COPY_A_TO_D equ     $09F0     ; A to D copy: USE_A|USE_D, LF=$F0
BLIT_TEMPORAL_SIZE  equ     (12<<6)|13 ; 12 rows height, 13 words width per plane
BLIT_SLOW_SIZE      equ     (3<<6)|13  ; 3 rows height, 13 words width per plane

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

; void UpdateCopperHalfPointerAsm(a0=CopperList, d0=HalfFrame)

_UpdateCopperHalfPointerAsm:
        lea     HAM_COPPER_HALFRATE_BPLPTR_BYTES(a0),a0 ; get half-rate pointer value slot
        movea.l d0,a1                    ; use half-rate frame pointer
        move.l  a1,d0                    ; load half-rate plane 0 pointer
        swap    d0                       ; select high word
        move.w  d0,(a0)                  ; write plane 0 high word
        swap    d0                       ; select low word
        move.w  d0,4(a0)                 ; write plane 0 low word
        lea     HAM_HALFRATE_PLANE_BYTES(a1),a1 ; advance to half-rate plane 1
        move.l  a1,d0                    ; load half-rate plane 1 pointer
        swap    d0                       ; select high word
        move.w  d0,8(a0)                 ; write plane 1 high word
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
        rts                              ; return to caller

; void CopyHamSlowRowsAndUpdateCopperAsm(a0=DynamicFrame, a1=SlowRows, a2=CopperList, d0=HalfFrame)
_CopyHamSlowRowsAndUpdateCopperAsm::
        move.l  a0,-(sp)                 ; save dynamic frame pointer for the slow copy
        move.l  a1,-(sp)                 ; save slow row source pointer for the slow copy
        movea.l a2,a0                    ; use copper list pointer for early pointer patching
        bsr.w   _UpdateCopperHalfPointerAsm ; patch inactive copper list while beam catches up
        movea.l (sp)+,a1                 ; restore slow row source pointer
        movea.l (sp)+,a0                 ; restore dynamic frame pointer
        btst.b  #0,VPOSR+1                ; test PAL line bit 8 before touching dynamic slow rows
        bne.s   .wait_dynamic_low         ; after line 255: only low-byte safety remains
        move.b  VPOSR+2,d1                ; read current low vertical beam byte
        cmp.b   #HAM_CORE_DONE_LOW,d1     ; detect wrap into the next frame
        blo.s   .dynamic_safe             ; copying is safe after the old frame wrapped away
.wait_dynamic_high:
        btst.b  #0,VPOSR+1                ; wait for the row-49 slow area after line 255
        beq.s   .wait_dynamic_high        ; stay while the beam is before the wrap line
.wait_dynamic_low:
        cmp.b   #HAM_DYNAMIC_DONE_LOW,VPOSR+2 ; wait for first line below slow rows
        blo.s   .wait_dynamic_low         ; stay while the beam still reads slow rows
.dynamic_safe:
        lea     HAM_SLOW_DEST_OFFSET(a0),a0 ; dest: slow rows start in plane 0
.bws0:  btst.b  #DMAB_BLITTER,DMACONR     ; wait for blitter idle (BBUSY=1=busy, 0=idle)
        bne.s   .bws0                     ; loop while busy
        move.w  #BLTCON0_COPY_A_TO_D,BLTCON0 ; A to D copy minterm
        clr.w   BLTCON1                   ; no shift, no fill
        move.w  #$FFFF,BLTAFWM            ; full first-word mask
        move.w  #$FFFF,BLTALWM            ; full last-word mask
        clr.w   BLTAMOD                   ; source rows contiguous within plane
        clr.w   BLTDMOD                   ; dest rows contiguous within plane
        move.l  a1,d0
        swap    d0
        move.w  d0,BLTAPTH                ; plane 0: source high word
        swap    d0
        move.w  d0,BLTAPTL                ; plane 0: source low word
        move.l  a0,d0
        swap    d0
        move.w  d0,BLTDPTH                ; plane 0: dest high word
        swap    d0
        move.w  d0,BLTDPTL                ; plane 0: dest low word
        move.w  #BLIT_SLOW_SIZE,BLTSIZE   ; fire plane 0; blitter starts
        lea     HAM_SLOW_PLANE_BYTES(a1),a1 ; source advance to plane 1
        lea     HAM_DYNAMIC_PLANE_BYTES(a0),a0 ; dest advance to plane 1
.bws1:  btst.b  #DMAB_BLITTER,DMACONR     ; wait for plane 0 blit done
        bne.s   .bws1
        move.l  a1,d0
        swap    d0
        move.w  d0,BLTAPTH                ; plane 1: source high word
        swap    d0
        move.w  d0,BLTAPTL                ; plane 1: source low word
        move.l  a0,d0
        swap    d0
        move.w  d0,BLTDPTH                ; plane 1: dest high word
        swap    d0
        move.w  d0,BLTDPTL                ; plane 1: dest low word
        move.w  #BLIT_SLOW_SIZE,BLTSIZE   ; fire plane 1
        lea     HAM_SLOW_PLANE_BYTES(a1),a1 ; source advance to plane 2
        lea     HAM_DYNAMIC_PLANE_BYTES(a0),a0 ; dest advance to plane 2
.bws2:  btst.b  #DMAB_BLITTER,DMACONR     ; wait for plane 1 blit done
        bne.s   .bws2
        move.l  a1,d0
        swap    d0
        move.w  d0,BLTAPTH                ; plane 2: source high word
        swap    d0
        move.w  d0,BLTAPTL                ; plane 2: source low word
        move.l  a0,d0
        swap    d0
        move.w  d0,BLTDPTH                ; plane 2: dest high word
        swap    d0
        move.w  d0,BLTDPTL                ; plane 2: dest low word
        move.w  #BLIT_SLOW_SIZE,BLTSIZE   ; fire plane 2
        lea     HAM_SLOW_PLANE_BYTES(a1),a1 ; source advance to plane 3
        lea     HAM_DYNAMIC_PLANE_BYTES(a0),a0 ; dest advance to plane 3
.bws3:  btst.b  #DMAB_BLITTER,DMACONR     ; wait for plane 2 blit done
        bne.s   .bws3
        move.l  a1,d0
        swap    d0
        move.w  d0,BLTAPTH                ; plane 3: source high word
        swap    d0
        move.w  d0,BLTAPTL                ; plane 3: source low word
        move.l  a0,d0
        swap    d0
        move.w  d0,BLTDPTH                ; plane 3: dest high word
        swap    d0
        move.w  d0,BLTDPTL                ; plane 3: dest low word
        move.w  #BLIT_SLOW_SIZE,BLTSIZE   ; fire plane 3; return without waiting
        rts                              ; plane 3 blit runs in parallel with CPU

; void CopyHamTemporalUpperRowsAsm(a0=TargetDynamicFrame, a1=SourceDynamicFrame)
; Uses blitter for A->D copy of upper temporal half (rows 2-13), all 4 planes.
; Returns immediately after firing plane 3; WaitBlitterDoneAsm must be called before
; writing to the same region again.
_CopyHamTemporalUpperRowsAsm::
.bwu0:  btst.b  #DMAB_BLITTER,DMACONR     ; wait for blitter idle (BBUSY=1=busy, 0=idle)
        bne.s   .bwu0                     ; loop while busy
        move.w  #BLTCON0_COPY_A_TO_D,BLTCON0 ; A to D copy minterm
        clr.w   BLTCON1                   ; no shift, no fill
        move.w  #$FFFF,BLTAFWM            ; full first-word mask
        move.w  #$FFFF,BLTALWM            ; full last-word mask
        clr.w   BLTAMOD                   ; source rows contiguous within plane
        clr.w   BLTDMOD                   ; dest rows contiguous within plane
        lea     HAM_TEMPORAL_UPPER_DEST_OFFSET(a0),a0 ; dest plane 0 start
        lea     HAM_TEMPORAL_UPPER_DEST_OFFSET(a1),a1 ; source plane 0 start
        move.l  a1,d0
        swap    d0
        move.w  d0,BLTAPTH                ; plane 0: source high word
        swap    d0
        move.w  d0,BLTAPTL                ; plane 0: source low word
        move.l  a0,d0
        swap    d0
        move.w  d0,BLTDPTH                ; plane 0: dest high word
        swap    d0
        move.w  d0,BLTDPTL                ; plane 0: dest low word
        move.w  #BLIT_TEMPORAL_SIZE,BLTSIZE ; fire plane 0; blitter starts
        lea     HAM_DYNAMIC_PLANE_BYTES(a0),a0 ; advance dest to plane 1
        lea     HAM_DYNAMIC_PLANE_BYTES(a1),a1 ; advance source to plane 1
.bwu1:  btst.b  #DMAB_BLITTER,DMACONR     ; wait for plane 0 blit done
        bne.s   .bwu1
        move.l  a1,d0
        swap    d0
        move.w  d0,BLTAPTH                ; plane 1: source high word
        swap    d0
        move.w  d0,BLTAPTL                ; plane 1: source low word
        move.l  a0,d0
        swap    d0
        move.w  d0,BLTDPTH                ; plane 1: dest high word
        swap    d0
        move.w  d0,BLTDPTL                ; plane 1: dest low word
        move.w  #BLIT_TEMPORAL_SIZE,BLTSIZE ; fire plane 1
        lea     HAM_DYNAMIC_PLANE_BYTES(a0),a0 ; advance dest to plane 2
        lea     HAM_DYNAMIC_PLANE_BYTES(a1),a1 ; advance source to plane 2
.bwu2:  btst.b  #DMAB_BLITTER,DMACONR     ; wait for plane 1 blit done
        bne.s   .bwu2
        move.l  a1,d0
        swap    d0
        move.w  d0,BLTAPTH                ; plane 2: source high word
        swap    d0
        move.w  d0,BLTAPTL                ; plane 2: source low word
        move.l  a0,d0
        swap    d0
        move.w  d0,BLTDPTH                ; plane 2: dest high word
        swap    d0
        move.w  d0,BLTDPTL                ; plane 2: dest low word
        move.w  #BLIT_TEMPORAL_SIZE,BLTSIZE ; fire plane 2
        lea     HAM_DYNAMIC_PLANE_BYTES(a0),a0 ; advance dest to plane 3
        lea     HAM_DYNAMIC_PLANE_BYTES(a1),a1 ; advance source to plane 3
.bwu3:  btst.b  #DMAB_BLITTER,DMACONR     ; wait for plane 2 blit done
        bne.s   .bwu3
        move.l  a1,d0
        swap    d0
        move.w  d0,BLTAPTH                ; plane 3: source high word
        swap    d0
        move.w  d0,BLTAPTL                ; plane 3: source low word
        move.l  a0,d0
        swap    d0
        move.w  d0,BLTDPTH                ; plane 3: dest high word
        swap    d0
        move.w  d0,BLTDPTL                ; plane 3: dest low word
        move.w  #BLIT_TEMPORAL_SIZE,BLTSIZE ; fire plane 3; return without waiting
        rts                               ; plane 3 blit runs in parallel with CPU

; void CopyHamTemporalLowerRowsAsm(a0=TargetDynamicFrame, a1=SourceDynamicFrame)
; Uses blitter for A->D copy of lower temporal half (rows 14-25), all 4 planes.
; Returns immediately after firing plane 3; WaitBlitterDoneAsm must be called before
; writing to the same region again.
_CopyHamTemporalLowerRowsAsm::
.bwl0:  btst.b  #DMAB_BLITTER,DMACONR     ; wait for blitter idle (BBUSY=1=busy, 0=idle)
        bne.s   .bwl0                     ; loop while busy
        move.w  #BLTCON0_COPY_A_TO_D,BLTCON0 ; A to D copy minterm
        clr.w   BLTCON1                   ; no shift, no fill
        move.w  #$FFFF,BLTAFWM            ; full first-word mask
        move.w  #$FFFF,BLTALWM            ; full last-word mask
        clr.w   BLTAMOD                   ; source rows contiguous within plane
        clr.w   BLTDMOD                   ; dest rows contiguous within plane
        lea     HAM_TEMPORAL_LOWER_DEST_OFFSET(a0),a0 ; dest plane 0 start
        lea     HAM_TEMPORAL_LOWER_DEST_OFFSET(a1),a1 ; source plane 0 start
        move.l  a1,d0
        swap    d0
        move.w  d0,BLTAPTH                ; plane 0: source high word
        swap    d0
        move.w  d0,BLTAPTL                ; plane 0: source low word
        move.l  a0,d0
        swap    d0
        move.w  d0,BLTDPTH                ; plane 0: dest high word
        swap    d0
        move.w  d0,BLTDPTL                ; plane 0: dest low word
        move.w  #BLIT_TEMPORAL_SIZE,BLTSIZE ; fire plane 0; blitter starts
        lea     HAM_DYNAMIC_PLANE_BYTES(a0),a0 ; advance dest to plane 1
        lea     HAM_DYNAMIC_PLANE_BYTES(a1),a1 ; advance source to plane 1
.bwl1:  btst.b  #DMAB_BLITTER,DMACONR     ; wait for plane 0 blit done
        bne.s   .bwl1
        move.l  a1,d0
        swap    d0
        move.w  d0,BLTAPTH                ; plane 1: source high word
        swap    d0
        move.w  d0,BLTAPTL                ; plane 1: source low word
        move.l  a0,d0
        swap    d0
        move.w  d0,BLTDPTH                ; plane 1: dest high word
        swap    d0
        move.w  d0,BLTDPTL                ; plane 1: dest low word
        move.w  #BLIT_TEMPORAL_SIZE,BLTSIZE ; fire plane 1
        lea     HAM_DYNAMIC_PLANE_BYTES(a0),a0 ; advance dest to plane 2
        lea     HAM_DYNAMIC_PLANE_BYTES(a1),a1 ; advance source to plane 2
.bwl2:  btst.b  #DMAB_BLITTER,DMACONR     ; wait for plane 1 blit done
        bne.s   .bwl2
        move.l  a1,d0
        swap    d0
        move.w  d0,BLTAPTH                ; plane 2: source high word
        swap    d0
        move.w  d0,BLTAPTL                ; plane 2: source low word
        move.l  a0,d0
        swap    d0
        move.w  d0,BLTDPTH                ; plane 2: dest high word
        swap    d0
        move.w  d0,BLTDPTL                ; plane 2: dest low word
        move.w  #BLIT_TEMPORAL_SIZE,BLTSIZE ; fire plane 2
        lea     HAM_DYNAMIC_PLANE_BYTES(a0),a0 ; advance dest to plane 3
        lea     HAM_DYNAMIC_PLANE_BYTES(a1),a1 ; advance source to plane 3
.bwl3:  btst.b  #DMAB_BLITTER,DMACONR     ; wait for plane 2 blit done
        bne.s   .bwl3
        move.l  a1,d0
        swap    d0
        move.w  d0,BLTAPTH                ; plane 3: source high word
        swap    d0
        move.w  d0,BLTAPTL                ; plane 3: source low word
        move.l  a0,d0
        swap    d0
        move.w  d0,BLTDPTH                ; plane 3: dest high word
        swap    d0
        move.w  d0,BLTDPTL                ; plane 3: dest low word
        move.w  #BLIT_TEMPORAL_SIZE,BLTSIZE ; fire plane 3; return without waiting
        rts                               ; plane 3 blit runs in parallel with CPU

; void WaitBlitterDoneAsm(void)
_WaitBlitterDoneAsm::
.wbd:   btst.b  #DMAB_BLITTER,DMACONR     ; test BBUSY (bit 6 of high byte = $DFF002)
        bne.s   .wbd                      ; loop while busy (BBUSY=1)
        rts                               ; return when idle (BBUSY=0)

; void RenderHamTemporalUpperRowsAsm(a0=Base, a1=TextureCellsMid, a2=UOffsetTableMid,
;                                      a3=PairTables, d0=DuDx, d1=DvDx,
;                                      d4=RowU, d5=RowV)

_RenderHamTemporalUpperRowsAsm::
        btst.b  #0,VPOSR+1                ; test PAL line bit 8 before touching temporal rows
        bne.s   .temporal_render_safe     ; rendering is safe in lower border/vblank
        cmp.b   #HAM_TEMPORAL_UPPER_DONE_LOW,VPOSR+2 ; check if this temporal half is already off-screen
        bhs.s   .temporal_render_safe     ; render immediately when this temporal half is safe
.wait_temporal_render:
        cmp.b   #HAM_TEMPORAL_UPPER_DONE_LOW,VPOSR+2 ; wait for first line below this temporal half
        blo.s   .wait_temporal_render     ; stay while the beam still reads those rows
.temporal_render_safe:
        movem.l d2-d7/a3-a6,-(sp)        ; save used C registers

        move.w  d0,d2                    ; d2 = horizontal U step
        move.w  d1,d3                    ; d3 = horizontal V step
        move.w  d4,d0                    ; d0 = row 0 U
        move.w  d5,d1                    ; d1 = row 0 V
        movea.l a3,a6                    ; a6 = interleaved pair table base

        move.w  d3,d6                    ; build temporal start U offset from DvDx
        add.w   d6,d6                    ; d6 = DvDx * 2
        sub.w   d6,d0                    ; start U at temporal row 2

        move.w  d2,d6                    ; build temporal start V offset from DuDx
        add.w   d6,d6                    ; d6 = DuDx * 2
        add.w   d6,d1                    ; start V at temporal row 2

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
        lea     RenderHamTemporalUpperRowsAsmRowUDelta+2(pc),a5 ; get temporal U delta immediate
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
        lea     RenderHamTemporalUpperRowsAsmRowVDelta+2(pc),a5 ; get temporal V delta immediate
        move.w  d6,(a5)                  ; patch temporal V delta

        moveq   #HAM_TEMPORAL_HALF_ROWS-2,d5        ; d5 = temporal half row transition counter
        lea     HAM_TEMPORAL_UPPER_DEST_OFFSET(a0),a3 ; a3 = temporal plane 0 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a3),a4 ; a4 = temporal plane 1 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a4),a5 ; a5 = temporal plane 2 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a5),a0 ; a0 = temporal plane 3 write pointer
RenderHamTemporalUpperRowsAsmRowLoop:
        bsr.w   RenderHamSharedRow        ; render temporal row and leave d0/d1 at row end
RenderHamTemporalUpperRowsAsmRowUDelta:
        add.w   #0,d0                    ; advance U to next temporal row
RenderHamTemporalUpperRowsAsmRowVDelta:
        add.w   #0,d1                    ; advance V to next temporal row
        dbra    d5,RenderHamTemporalUpperRowsAsmRowLoop         ; render next temporal row with transition
        bsr.w   RenderHamSharedRow        ; render final temporal row without unused delta

        movem.l (sp)+,d2-d7/a3-a6        ; restore used C registers
        rts                              ; return to C

; void RenderHamTemporalLowerRowsAsm(a0=Base, a1=TextureCellsMid, a2=UOffsetTableMid,
;                                      a3=PairTables, d0=DuDx, d1=DvDx,
;                                      d4=RowU, d5=RowV)

_RenderHamTemporalLowerRowsAsm::
        btst.b  #0,VPOSR+1                ; test PAL line bit 8 before touching temporal rows
        bne.s   .temporal_render_safe     ; rendering is safe in lower border/vblank
        cmp.b   #HAM_TEMPORAL_DONE_LOW,VPOSR+2 ; check if this temporal half is already off-screen
        bhs.s   .temporal_render_safe     ; render immediately when this temporal half is safe
.wait_temporal_render:
        cmp.b   #HAM_TEMPORAL_DONE_LOW,VPOSR+2 ; wait for first line below this temporal half
        blo.s   .wait_temporal_render     ; stay while the beam still reads those rows
.temporal_render_safe:
        movem.l d2-d7/a3-a6,-(sp)        ; save used C registers

        move.w  d0,d2                    ; d2 = horizontal U step
        move.w  d1,d3                    ; d3 = horizontal V step
        move.w  d4,d0                    ; d0 = row 0 U
        move.w  d5,d1                    ; d1 = row 0 V
        movea.l a3,a6                    ; a6 = interleaved pair table base

        move.w  d3,d6                    ; build temporal start U offset from DvDx
        lsl.w   #4,d6                    ; d6 = DvDx * 16
        move.w  d3,d7                    ; d7 = DvDx
        add.w   d7,d7                    ; d7 = DvDx * 2
        sub.w   d7,d6                    ; d6 = DvDx * 14
        sub.w   d6,d0                    ; start U at temporal row 14

        move.w  d2,d6                    ; build temporal start V offset from DuDx
        lsl.w   #4,d6                    ; d6 = DuDx * 16
        move.w  d2,d7                    ; d7 = DuDx
        add.w   d7,d7                    ; d7 = DuDx * 2
        sub.w   d7,d6                    ; d6 = DuDx * 14
        add.w   d6,d1                    ; start V at temporal row 14

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
        lea     RenderHamTemporalLowerRowsAsmRowUDelta+2(pc),a5 ; get temporal U delta immediate
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
        lea     RenderHamTemporalLowerRowsAsmRowVDelta+2(pc),a5 ; get temporal V delta immediate
        move.w  d6,(a5)                  ; patch temporal V delta

        moveq   #HAM_TEMPORAL_HALF_ROWS-2,d5        ; d5 = temporal half row transition counter
        lea     HAM_TEMPORAL_LOWER_DEST_OFFSET(a0),a3 ; a3 = temporal plane 0 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a3),a4 ; a4 = temporal plane 1 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a4),a5 ; a5 = temporal plane 2 write pointer
        lea     HAM_DYNAMIC_PLANE_BYTES(a5),a0 ; a0 = temporal plane 3 write pointer
RenderHamTemporalLowerRowsAsmRowLoop:
        bsr.w   RenderHamSharedRow        ; render temporal row and leave d0/d1 at row end
RenderHamTemporalLowerRowsAsmRowUDelta:
        add.w   #0,d0                    ; advance U to next temporal row
RenderHamTemporalLowerRowsAsmRowVDelta:
        add.w   #0,d1                    ; advance V to next temporal row
        dbra    d5,RenderHamTemporalLowerRowsAsmRowLoop         ; render next temporal row with transition
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
        lsl.w   #2,d7                    ; d7 = DvDx * 4
        sub.w   d7,d6                    ; d6 = DvDx * 28
        move.w  d3,d7                    ; d7 = DvDx
        add.w   d7,d7                    ; d7 = DvDx * 2
        sub.w   d7,d6                    ; d6 = DvDx * 26
        sub.w   d6,d0                    ; start U at half-rate row 26

        move.w  d2,d6                    ; build half-rate start V offset from DuDx
        lsl.w   #5,d6                    ; d6 = DuDx * 32
        move.w  d2,d7                    ; d7 = DuDx
        lsl.w   #2,d7                    ; d7 = DuDx * 4
        sub.w   d7,d6                    ; d6 = DuDx * 28
        move.w  d2,d7                    ; d7 = DuDx
        add.w   d7,d7                    ; d7 = DuDx * 2
        sub.w   d7,d6                    ; d6 = DuDx * 26
        add.w   d6,d1                    ; start V at half-rate row 26

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
        lsl.w   #4,d7                    ; d7 = DvDx * 16
        add.w   d7,d6                    ; d6 = DvDx * 48
        add.w   d3,d6                    ; d6 = DvDx * 49
        sub.w   d6,d0                    ; start U at slow-copy row 49

        move.w  d2,d6                    ; build slow-copy start V offset from DuDx
        lsl.w   #5,d6                    ; d6 = DuDx * 32
        move.w  d2,d7                    ; d7 = DuDx
        lsl.w   #4,d7                    ; d7 = DuDx * 16
        add.w   d7,d6                    ; d6 = DuDx * 48
        add.w   d2,d6                    ; d6 = DuDx * 49
        add.w   d6,d1                    ; start V at slow-copy row 49

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

