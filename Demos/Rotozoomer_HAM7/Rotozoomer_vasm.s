;**********************************************************************
;* 4x4 HAM7 Rotozoomer                                                *
;*                                                                    *
;* Stable HAM7 baseline:                                              *
;*   - assembler direct render into proven temp layout                *
;*   - blitter extract into the 4 DMA bitplanes                       *
;**********************************************************************

    machine 68000

    xdef _RenderScrambledRowPhase0Asm
    xdef _RenderPhase0ScrambledRowsAsm
    xdef _RenderPhase0TempRowsAsm
    xdef _CpuSwapScrambledRowAsm
    xdef _CpuSwapScrambledFrameAsm
    xdef _RunC2PExtractAsm
    xdef _ExpandPlanarRows4xAsm

    xref _Ham7Phase0RGPack
    xref _Ham7Phase0BluePack

CUSTOM_BASE             equ $dff000
DMACONR_OFF             equ $0002
BLTCON0_OFF             equ $0040
BLTAFWM_OFF             equ $0044
BLTBPTH_OFF             equ $004c
BLTAPTH_OFF             equ $0050
BLTDPTH_OFF             equ $0054
BLTSIZE_OFF             equ $0058
BLTBMOD_OFF             equ $0062
BLTAMOD_OFF             equ $0064
BLTDMOD_OFF             equ $0066
BLTCDAT_OFF             equ $0070

ROTO_COLUMNS            equ 28
ROTO_FETCH_BYTES        equ 14
ROTO_ROWS               equ 48
ROTO_DISPLAY_ROWS       equ (ROTO_ROWS*4)
ROTO_ROW_BYTES          equ (ROTO_COLUMNS*2)
ROTO_DISPLAY_PLANE_BYTES equ (ROTO_FETCH_BYTES*ROTO_DISPLAY_ROWS)
ROTOFRAME_DUDX          equ 0
ROTOFRAME_DVDX          equ 2
ROTOFRAME_ROWS          equ 4
ROTOFRAME_ROWSTATE_SIZE equ 14
RROW_PREFIXHI        equ 0
RROW_PREFIXLO        equ 4
RROW_STARTU          equ 8
RROW_STARTV          equ 10
RROW_PREVGB          equ 12
ROTO_PLANE_BYTES        equ (ROTO_FETCH_BYTES*ROTO_ROWS)
ROTO_SCREEN_BYTES       equ (ROTO_PLANE_BYTES*4)
ROTO_C2P_BLTSIZE        equ ((ROTO_FETCH_BYTES*ROTO_ROWS*16)+1)

BLIT_EXTRACT_4_RIGHT    equ (($4de4<<16)|0)
BLIT_EXTRACT_4_LEFT     equ (($4dd8<<16)|2)

SWAP_GROUP macro
    move.l  (a0)+,d0
    move.l  (a0)+,d1
    move.l  d0,d2
    andi.l  #$ff00ff00,d2
    move.l  d1,d3
    lsr.l   #8,d3
    andi.l  #$00ff00ff,d3
    or.l    d3,d2
    move.l  d2,(a1)+
    lsl.l   #8,d0
    andi.l  #$ff00ff00,d0
    andi.l  #$00ff00ff,d1
    or.l    d1,d0
    move.l  d0,(a1)+
    endm

RENDER_ONE macro
    move.w  d1,d6
    andi.w  #$7f00,d6
    move.w  d0,d7
    lsr.w   #7,d7
    andi.w  #$00fe,d7
    add.w   d7,d6
    move.w  (a0,d6.w),d6

    move.w  d6,d7
    andi.w  #$000f,d7
    add.w   d5,d7
    add.w   d7,d7
    add.w   d7,d7
    move.l  (a3,d7.w),d7
    move.w  d7,d5
    swap    d7

    lsr.w   #4,d6
    add.w   d4,d6
    add.w   d6,d6
    add.w   d6,d6
    move.l  (a2,d6.w),d6
    move.w  d6,d4
    swap    d6
    or.w    d6,d7

    add.w   d2,d0
    add.w   d3,d1
    endm

RENDER_ROW_TO_SCRAMBLED macro
    rept    ROTO_COLUMNS
        RENDER_ONE
        move.w  d7,(a1)+
    endr
    endm

STORE_SWAPPED_GROUP macro
    move.l  (a5),d6
    move.l  4(a5),d7
    move.l  d7,a6
    andi.l  #$ff00ff00,d6
    lsr.l   #8,d7
    andi.l  #$00ff00ff,d7
    or.l    d7,d6
    move.l  d6,(a1)+
    move.l  (a5),d6
    move.l  a6,d7
    lsl.l   #8,d6
    andi.l  #$ff00ff00,d6
    andi.l  #$00ff00ff,d7
    or.l    d7,d6
    move.l  d6,(a1)+
    endm

RENDER_GROUP_TO_TEMP macro
    RENDER_ONE
    move.w  d7,(a5)
    RENDER_ONE
    move.w  d7,2(a5)
    RENDER_ONE
    move.w  d7,4(a5)
    RENDER_ONE
    move.w  d7,6(a5)
    STORE_SWAPPED_GROUP
    endm

_RenderScrambledRowPhase0Asm:
    movem.l d2-d7/a2-a3,-(sp)
    lea     _Ham7Phase0RGPack,a2
    lea     _Ham7Phase0BluePack,a3
    moveq   #0,d4
    moveq   #0,d5

    RENDER_ROW_TO_SCRAMBLED

    movem.l (sp)+,d2-d7/a2-a3
    rts

_RenderPhase0ScrambledRowsAsm:
    movem.l d2-d7/a2-a6,-(sp)
    subq.l  #4,sp

    movea.l a0,a6
    move.w  ROTOFRAME_DUDX(a6),d2
    move.w  ROTOFRAME_DVDX(a6),d3
    lea     ROTOFRAME_ROWS(a6),a4
    movea.l a1,a0
    movea.l a2,a1
    move.l  a1,(sp)
    addi.l  #ROTO_SCREEN_BYTES,(sp)
    lea     _Ham7Phase0RGPack,a2
    lea     _Ham7Phase0BluePack,a3
.row_loop:
    move.w  (a4)+,d0
    move.w  (a4)+,d1
    moveq   #0,d4
    moveq   #0,d5
    RENDER_ROW_TO_SCRAMBLED
    cmpa.l  (sp),a1
    bne.s   .row_loop

    addq.l  #4,sp
    movem.l (sp)+,d2-d7/a2-a6
    rts

_RenderPhase0TempRowsAsm:
    movem.l d2-d7/a2-a6,-(sp)
    lea     -12(sp),sp
    movea.l sp,a5

    movea.l a0,a6
    move.w  ROTOFRAME_DUDX(a6),d2
    move.w  ROTOFRAME_DVDX(a6),d3
    lea     ROTOFRAME_ROWS(a6),a4
    movea.l a1,a0
    movea.l a2,a1
    move.l  a1,8(sp)
    addi.l  #ROTO_SCREEN_BYTES,8(sp)
    lea     _Ham7Phase0RGPack,a2
    lea     _Ham7Phase0BluePack,a3
.temp_row_loop:
    move.l  RROW_PREFIXHI(a4),(a1)+
    move.l  RROW_PREFIXLO(a4),(a1)+
    move.w  RROW_STARTU(a4),d0
    move.w  RROW_STARTV(a4),d1
    move.w  RROW_PREVGB(a4),d4
    move.w  d4,d5
    lsr.w   #8,d4
    andi.w  #$00ff,d5
    adda.w  #ROTOFRAME_ROWSTATE_SIZE,a4
    rept    ((ROTO_COLUMNS/4)-1)
        RENDER_GROUP_TO_TEMP
    endr
    cmpa.l  8(sp),a1
    bne.s   .temp_row_loop

    lea     12(sp),sp
    movem.l (sp)+,d2-d7/a2-a6
    rts

_CpuSwapScrambledRowAsm:
    movem.l d2-d3,-(sp)

    SWAP_GROUP
    SWAP_GROUP
    SWAP_GROUP
    SWAP_GROUP
    SWAP_GROUP
    SWAP_GROUP
    SWAP_GROUP

    movem.l (sp)+,d2-d3
    rts

_CpuSwapScrambledFrameAsm:
    movem.l d2-d3/d7,-(sp)

    moveq   #(ROTO_ROWS-1),d7
.row_loop:
    SWAP_GROUP
    SWAP_GROUP
    SWAP_GROUP
    SWAP_GROUP
    SWAP_GROUP
    SWAP_GROUP
    SWAP_GROUP
    dbra    d7,.row_loop

    movem.l (sp)+,d2-d3/d7
    rts

WaitBlit:
.wait:
    btst    #14,DMACONR_OFF(a6)
    bne.s   .wait
    rts

ExtractSetup:
    move.l  #$ffffffff,BLTAFWM_OFF(a6)
    clr.w   BLTDMOD_OFF(a6)
    move.w  #6,BLTBMOD_OFF(a6)
    move.l  #$00060000,BLTAMOD_OFF(a6)
    move.w  #$0f0f,BLTCDAT_OFF(a6)
    rts

DoExtractRight:
    ; plane 3, ascending/right, launch 1/2
    move.l  #BLIT_EXTRACT_4_RIGHT,BLTCON0_OFF(a6)
    move.l  a0,BLTBPTH_OFF(a6)
    movea.l a0,a3
    adda.w  #2,a3
    move.l  a3,BLTAPTH_OFF(a6)
    movea.l a1,a3
    adda.w  #(ROTO_PLANE_BYTES*3),a3
    move.l  a3,BLTDPTH_OFF(a6)
    move.w  #ROTO_C2P_BLTSIZE,BLTSIZE_OFF(a6)
    bsr     WaitBlit
    move.w  #ROTO_C2P_BLTSIZE,BLTSIZE_OFF(a6)
    bsr     WaitBlit

    ; plane 1, ascending/right, launch 1/2
    movea.l a0,a3
    adda.w  #4,a3
    move.l  a3,BLTBPTH_OFF(a6)
    adda.w  #2,a3
    move.l  a3,BLTAPTH_OFF(a6)
    movea.l a1,a3
    adda.w  #ROTO_PLANE_BYTES,a3
    move.l  a3,BLTDPTH_OFF(a6)
    move.w  #ROTO_C2P_BLTSIZE,BLTSIZE_OFF(a6)
    bsr     WaitBlit
    move.w  #ROTO_C2P_BLTSIZE,BLTSIZE_OFF(a6)
    bsr     WaitBlit
    rts

DoExtractLeft:
    ; plane 2, descending/left, launch 1/2
    move.l  #BLIT_EXTRACT_4_LEFT,BLTCON0_OFF(a6)
    movea.l a0,a3
    adda.w  #(ROTO_SCREEN_BYTES-8),a3
    move.l  a3,BLTAPTH_OFF(a6)
    adda.w  #2,a3
    move.l  a3,BLTBPTH_OFF(a6)
    movea.l a1,a3
    adda.w  #((ROTO_PLANE_BYTES*3)-2),a3
    move.l  a3,BLTDPTH_OFF(a6)
    move.w  #ROTO_C2P_BLTSIZE,BLTSIZE_OFF(a6)
    bsr     WaitBlit
    move.w  #ROTO_C2P_BLTSIZE,BLTSIZE_OFF(a6)
    bsr     WaitBlit

    ; plane 0, descending/left, launch 1/2
    movea.l a0,a3
    adda.w  #(ROTO_SCREEN_BYTES-4),a3
    move.l  a3,BLTAPTH_OFF(a6)
    adda.w  #2,a3
    move.l  a3,BLTBPTH_OFF(a6)
    movea.l a1,a3
    adda.w  #(ROTO_PLANE_BYTES-2),a3
    move.l  a3,BLTDPTH_OFF(a6)
    move.w  #ROTO_C2P_BLTSIZE,BLTSIZE_OFF(a6)
    bsr     WaitBlit
    move.w  #ROTO_C2P_BLTSIZE,BLTSIZE_OFF(a6)
    bsr     WaitBlit
    rts

_RunC2PExtractAsm:
    movem.l d2-d7/a2-a6,-(sp)
    lea     CUSTOM_BASE,a6
    bsr     WaitBlit
    bsr     ExtractSetup
    bsr     DoExtractRight
    bsr     DoExtractLeft
    movem.l (sp)+,d2-d7/a2-a6
    rts

_ExpandPlanarRows4xAsm:
    movem.l d2-d7/a2-a5,-(sp)

    moveq   #3,d6
.plane_loop:
    movea.l a0,a2
    movea.l a1,a3
    moveq   #(ROTO_ROWS-1),d7
.row_loop:
    move.l  (a2)+,d0
    move.l  (a2)+,d1
    move.l  (a2)+,d2
    move.w  (a2)+,d3

    move.l  d0,(a3)
    move.l  d1,4(a3)
    move.l  d2,8(a3)
    move.w  d3,12(a3)

    move.l  d0,14(a3)
    move.l  d1,18(a3)
    move.l  d2,22(a3)
    move.w  d3,26(a3)

    move.l  d0,28(a3)
    move.l  d1,32(a3)
    move.l  d2,36(a3)
    move.w  d3,40(a3)

    move.l  d0,42(a3)
    move.l  d1,46(a3)
    move.l  d2,50(a3)
    move.w  d3,54(a3)

    lea     56(a3),a3
    dbra    d7,.row_loop

    movea.l a2,a0
    movea.l a3,a1
    dbra    d6,.plane_loop

    movem.l (sp)+,d2-d7/a2-a5
    rts


Ham7Phase0RedWord:
    dc.w $0000,$0008,$0080,$0088,$0800,$0808,$0880,$0888
    dc.w $8000,$8008,$8080,$8088,$8800,$8808,$8880,$8888

