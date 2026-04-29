;**********************************************************************
;* 4x4 HAM7 Rotozoomer                                                *
;*                                                                    *
;**********************************************************************

    machine 68000

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
ROTO_CHUNK_ROWS         equ 16
ROTOFRAME_DUDX          equ 0
ROTOFRAME_DVDX          equ 2
ROTOFRAME_ROWS          equ 4
ROTO_PLANE_BYTES        equ (ROTO_FETCH_BYTES*ROTO_ROWS)
ROTO_SCREEN_BYTES       equ (ROTO_PLANE_BYTES*4)
ROTO_CHUNK_BYTES        equ (ROTO_FETCH_BYTES*ROTO_CHUNK_ROWS*4)
ROTO_C2P_BLTSIZE        equ ((ROTO_PLANE_BYTES*32)+1)

BLIT_EXTRACT_4_RIGHT    equ (($4de4<<16)|0)
BLIT_EXTRACT_4_LEFT     equ (($4dd8<<16)|2)

RENDER_ONE macro
    move.w  d1,d6
    andi.w  #$7f00,d6
    move.w  d0,d7
    lsr.w   #7,d7
    andi.w  #$00fe,d7
    add.w   d7,d6
    move.w  (a0,d6.w),d7
    move.w  (a3,d6.w),d6
    add.w   d4,d7
    move.l  (a2,d7.w),d7
    move.w  d7,d4
    swap    d7
    or.w    d7,d6

    add.w   d2,d0
    add.w   d3,d1
    endm

STORE_SWAPPED_GROUP macro
    move.l  d7,a6
    move.l  d5,d6
    andi.l  #$ff00ff00,d5
    lsr.l   #8,d7
    andi.l  #$00ff00ff,d7
    or.l    d7,d5
    move.l  d5,(a1)+
    lsl.l   #8,d6
    andi.l  #$ff00ff00,d6
    move.l  a6,d7
    andi.l  #$00ff00ff,d7
    or.l    d7,d6
    move.l  d6,(a1)+
    endm

RENDER_GROUP_TO_TEMP macro
    RENDER_ONE
    move.w  d6,d5
    swap    d5
    RENDER_ONE
    move.w  d6,d5
    RENDER_ONE
    move.w  d6,d7
    swap    d7
    move.l  d7,a6
    RENDER_ONE
    move.l  a6,d7
    move.w  d6,d7
    STORE_SWAPPED_GROUP
    endm

_RenderPhase0TempRowsChunkAsm::
    movem.l d2-d7/a2-a6,-(sp)

    movea.l a0,a6
    move.w  ROTOFRAME_DUDX(a6),d2
    move.w  ROTOFRAME_DVDX(a6),d3
    lea     ROTOFRAME_ROWS(a6),a4
    movea.l a1,a0
    movea.l a2,a1
    movea.l a1,a5
    adda.w  #ROTO_CHUNK_BYTES,a5
    movea.l _Ham7Phase0RGPack,a2
    movea.l _TextureBlueWord,a3
.temp_row_loop:
    move.w  (a4)+,d0
    move.w  (a4)+,d1
    moveq   #0,d4
    rept    (ROTO_COLUMNS/4)
        RENDER_GROUP_TO_TEMP
    endr
    cmpa.l  a5,a1
    bne.w   .temp_row_loop

    movem.l (sp)+,d2-d7/a2-a6
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
    ; plane 3, ascending/right, full plane
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

    ; plane 1, ascending/right, full plane
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
    rts

DoExtractLeft:
    ; plane 2, descending/left, full plane
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

    ; plane 0, descending/left, full plane
    movea.l a0,a3
    adda.w  #(ROTO_SCREEN_BYTES-4),a3
    move.l  a3,BLTAPTH_OFF(a6)
    adda.w  #2,a3
    move.l  a3,BLTBPTH_OFF(a6)
    movea.l a1,a3
    adda.w  #(ROTO_PLANE_BYTES-2),a3
    move.l  a3,BLTDPTH_OFF(a6)
    move.w  #ROTO_C2P_BLTSIZE,BLTSIZE_OFF(a6)
    rts

_StartC2PExtractAsm::
    movem.l a3/a6,-(sp)
    lea     CUSTOM_BASE,a6
    bsr     WaitBlit
    bsr     ExtractSetup
    bsr     DoExtractRight
    bsr     DoExtractLeft
    movem.l (sp)+,a3/a6
    rts

_StartC2PPlane3Asm::
    movem.l a3/a6,-(sp)
    lea     CUSTOM_BASE,a6
    bsr     ExtractSetup
    move.l  #BLIT_EXTRACT_4_RIGHT,BLTCON0_OFF(a6)
    move.l  a0,BLTBPTH_OFF(a6)
    movea.l a0,a3
    adda.w  #2,a3
    move.l  a3,BLTAPTH_OFF(a6)
    movea.l a1,a3
    adda.w  #(ROTO_PLANE_BYTES*3),a3
    move.l  a3,BLTDPTH_OFF(a6)
    move.w  #ROTO_C2P_BLTSIZE,BLTSIZE_OFF(a6)
    movem.l (sp)+,a3/a6
    rts

_StartC2PPlane1Asm::
    movem.l a3/a6,-(sp)
    lea     CUSTOM_BASE,a6
    move.l  #BLIT_EXTRACT_4_RIGHT,BLTCON0_OFF(a6)
    movea.l a0,a3
    adda.w  #4,a3
    move.l  a3,BLTBPTH_OFF(a6)
    adda.w  #2,a3
    move.l  a3,BLTAPTH_OFF(a6)
    movea.l a1,a3
    adda.w  #ROTO_PLANE_BYTES,a3
    move.l  a3,BLTDPTH_OFF(a6)
    move.w  #ROTO_C2P_BLTSIZE,BLTSIZE_OFF(a6)
    movem.l (sp)+,a3/a6
    rts

_StartC2PPlane2Asm::
    movem.l a3/a6,-(sp)
    lea     CUSTOM_BASE,a6
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
    movem.l (sp)+,a3/a6
    rts

_StartC2PPlane0Asm::
    movem.l a3/a6,-(sp)
    lea     CUSTOM_BASE,a6
    move.l  #BLIT_EXTRACT_4_LEFT,BLTCON0_OFF(a6)
    movea.l a0,a3
    adda.w  #(ROTO_SCREEN_BYTES-4),a3
    move.l  a3,BLTAPTH_OFF(a6)
    adda.w  #2,a3
    move.l  a3,BLTBPTH_OFF(a6)
    movea.l a1,a3
    adda.w  #(ROTO_PLANE_BYTES-2),a3
    move.l  a3,BLTDPTH_OFF(a6)
    move.w  #ROTO_C2P_BLTSIZE,BLTSIZE_OFF(a6)
    movem.l (sp)+,a3/a6
    rts

_RunC2PExtractAsm::
    movem.l a3/a6,-(sp)
    lea     CUSTOM_BASE,a6
    bsr     WaitBlit
    bsr     ExtractSetup
    bsr     DoExtractRight
    bsr     DoExtractLeft
    bsr     WaitBlit
    movem.l (sp)+,a3/a6
    rts
