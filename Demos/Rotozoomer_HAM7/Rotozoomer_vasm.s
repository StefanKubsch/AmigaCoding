;**********************************************************************
;* 4x4 HAM7 Rotozoomer                                                *
;*                                                                    *
;* Stable HAM7 baseline:                                              *
;*   - CPU sample + phase-0 HAM7 encode to scrambled words            *
;*   - assembler row-swap into proven temp layout                     *
;*   - blitter extract into the 4 DMA bitplanes                       *
;**********************************************************************

    machine 68000

    xdef _CpuSwapScrambledRowAsm
    xdef _RunC2PExtractAsm

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
