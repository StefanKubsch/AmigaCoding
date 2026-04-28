;**********************************************************************
;* 4x4 HAM7 Rotozoomer                                                *
;*                                                                    *
;* Debug stage: reference phase-0 direct vs blitter-C2P compare       *
;*                                                                    *
;* The proven direct phase-0 HAM7 path is shown in the top half.      *
;* The bottom half is generated from scrambled encoded words through   *
;* the blitter C2P chain below.                                       *
;**********************************************************************

    machine 68000

    xdef _RunC2PBlitAsm

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
BLTCDAT_OFF             equ $0070

ROTO_COLUMNS            equ 28
ROTO_ROWS               equ 48
ROTO_FETCH_BYTES        equ 14
ROTO_PLANE_BYTES        equ (ROTO_FETCH_BYTES*ROTO_ROWS)
ROTO_SCREEN_BYTES       equ (ROTO_PLANE_BYTES*4)
ROTO_C2P_BLTSIZE        equ ((ROTO_FETCH_BYTES*ROTO_ROWS*16)+1)

BLIT_SWAP_8_RIGHT       equ (($8dca<<16)|0)
BLIT_SWAP_8_LEFT        equ (($8dd8<<16)|2)
BLIT_EXTRACT_4_RIGHT    equ (($4dca<<16)|0)
BLIT_EXTRACT_4_LEFT     equ (($4dd8<<16)|2)

WaitBlit:
.wait:
    btst    #14,DMACONR_OFF(a6)
    bne.s   .wait
    rts

; -----------------------------------------------------------------------------
; void RunC2PBlitAsm(__reg("a0") const UWORD *Chunky,
;                    __reg("a1") UBYTE *Screen,
;                    __reg("a2") UBYTE *Temp)
;
; Chunky words are expected in the DESiRE-style scrambled RGBB format:
;   ScrambledRed[encR] | ScrambledGreen[encG] | ScrambledBlue[encB]
; -----------------------------------------------------------------------------
_RunC2PBlitAsm:
    movem.l d2-d7/a2-a6,-(sp)
    lea     CUSTOM_BASE,a6
    bsr     WaitBlit

    ; 8x2 swap right, pass 1/2
    move.w  #4,BLTBMOD_OFF(a6)
    move.l  #$00040004,BLTAMOD_OFF(a6)
    move.w  #$00ff,BLTCDAT_OFF(a6)
    move.l  #$ffffffff,BLTAFWM_OFF(a6)
    move.l  #BLIT_SWAP_8_RIGHT,BLTCON0_OFF(a6)
    move.l  a0,BLTBPTH_OFF(a6)
    movea.l a0,a3
    adda.w  #4,a3
    move.l  a3,BLTAPTH_OFF(a6)
    move.l  a2,BLTDPTH_OFF(a6)
    move.w  #(ROTO_C2P_BLTSIZE+1),BLTSIZE_OFF(a6)
    bsr     WaitBlit
    move.w  #(ROTO_C2P_BLTSIZE+1),BLTSIZE_OFF(a6)
    bsr     WaitBlit

    ; 8x2 swap left, pass 1/2 (descending)
    move.l  #BLIT_SWAP_8_LEFT,BLTCON0_OFF(a6)
    movea.l a0,a3
    adda.w  #(ROTO_SCREEN_BYTES-6),a3
    move.l  a3,BLTAPTH_OFF(a6)
    adda.w  #4,a3
    move.l  a3,BLTBPTH_OFF(a6)
    movea.l a2,a3
    adda.w  #(ROTO_SCREEN_BYTES-2),a3
    move.l  a3,BLTDPTH_OFF(a6)
    move.w  #(ROTO_C2P_BLTSIZE+1),BLTSIZE_OFF(a6)
    bsr     WaitBlit
    move.w  #(ROTO_C2P_BLTSIZE+1),BLTSIZE_OFF(a6)
    bsr     WaitBlit

    ; Extract plane 3, pass 1/2
    move.w  #6,BLTBMOD_OFF(a6)
    move.l  #$00060000,BLTAMOD_OFF(a6)
    move.w  #$0f0f,BLTCDAT_OFF(a6)
    move.l  #BLIT_EXTRACT_4_RIGHT,BLTCON0_OFF(a6)
    move.l  a2,BLTBPTH_OFF(a6)
    movea.l a2,a3
    adda.w  #2,a3
    move.l  a3,BLTAPTH_OFF(a6)
    movea.l a1,a3
    adda.w  #(ROTO_PLANE_BYTES*3),a3
    move.l  a3,BLTDPTH_OFF(a6)
    move.w  #ROTO_C2P_BLTSIZE,BLTSIZE_OFF(a6)
    bsr     WaitBlit
    move.w  #ROTO_C2P_BLTSIZE,BLTSIZE_OFF(a6)
    bsr     WaitBlit

    ; Extract plane 1, pass 1/2
    movea.l a2,a3
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

    ; Extract plane 2, pass 1/2 (descending)
    move.l  #BLIT_EXTRACT_4_LEFT,BLTCON0_OFF(a6)
    movea.l a2,a3
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

    ; Extract plane 0, pass 1/2 (descending)
    movea.l a2,a3
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

    movem.l (sp)+,d2-d7/a2-a6
    rts
