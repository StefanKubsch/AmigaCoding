;
; Projection assumptions:
;   FP_SHIFT                = 8
;   SRC_COORD_BIAS          = 100
;   PROJ_COORD_BIAS         = 125
;   Z_OFFSET - PROJ_Z_MIN   = 124
;   CENTER_X / CENTER_Y     = 160 / 128
;   SCREEN_WORDS_PER_ROW    = 20
;
; The C side passes prebiased table bases:
;   RotC / RotS            -> base + SRC_COORD_BIAS
;   ProjRows               -> base + (Z_OFFSET - PROJ_Z_MIN)
;   each ProjRows entry    -> row start + PROJ_COORD_BIAS
;
; ScreenRowByteBase is internal in this asm file and indexed by projected Y
; around CENTER_Y using a base address of table + 256 bytes.
;
; BuildStaticWordMaskFrameAsm additionally assumes POINT3D8 is a packed 3-byte struct.
;

    machine 68000

    xdef    BuildMorphWordMaskFrameAdvanceAsm
    xdef    _BuildMorphWordMaskFrameAdvanceAsm
    xdef    BuildStaticWordMaskFrameAsm
    xdef    _BuildStaticWordMaskFrameAsm
    xdef    UpdateFrameWordsAsm
    xdef    _UpdateFrameWordsAsm

MSAVE_SIZE          equ     44      ; d2-d7/a2-a6
SSAVE_SIZE          equ     44      ; d2-d7/a2-a6
USAVE_SIZE          equ     36      ; d3-d7/a2-a5

MARG_CUR            equ     MSAVE_SIZE+4
MARG_STEP           equ     MSAVE_SIZE+8
MARG_POINTCOUNT     equ     MSAVE_SIZE+12
MARG_ROTC           equ     MSAVE_SIZE+16
MARG_ROTS           equ     MSAVE_SIZE+20
MARG_PROJROWS       equ     MSAVE_SIZE+24
MARG_WORDMASKACCUM  equ     MSAVE_SIZE+28
MARG_FRAMEWORDINDEX equ     MSAVE_SIZE+32

SARG_POINTS         equ     SSAVE_SIZE+4
SARG_POINTCOUNT     equ     SSAVE_SIZE+8
SARG_ROTC           equ     SSAVE_SIZE+12
SARG_ROTS           equ     SSAVE_SIZE+16
SARG_PROJROWS       equ     SSAVE_SIZE+20
SARG_WORDMASKACCUM  equ     SSAVE_SIZE+24
SARG_FRAMEWORDINDEX equ     SSAVE_SIZE+28

UARG_PLANE          equ     USAVE_SIZE+4
UARG_PREV           equ     USAVE_SIZE+8
UARG_PREVCOUNT      equ     USAVE_SIZE+12
UARG_FRAMEWORDCOUNT equ     USAVE_SIZE+16
UARG_WORDMASKACCUM  equ     USAVE_SIZE+20
UARG_FRAMEWORDINDEX equ     USAVE_SIZE+24

CENTER_X            equ     160
CENTER_Y            equ     128
FP_SHIFT            equ     8

; ----------------------------------------------------------------------
; UWORD BuildMorphWordMaskFrameAdvanceAsm(...)
; ----------------------------------------------------------------------

BuildMorphWordMaskFrameAdvanceAsm:
_BuildMorphWordMaskFrameAdvanceAsm:
    movem.l d2-d7/a2-a6,-(sp)

    movea.l MARG_CUR(sp),a0
    movea.l MARG_STEP(sp),a1
    move.l  MARG_POINTCOUNT(sp),d7
    beq.w   .m_done_empty

    subq.w  #1,d7
    movea.l MARG_ROTC(sp),a2
    movea.l MARG_ROTS(sp),a3
    movea.l MARG_PROJROWS(sp),a4
    movea.l MARG_WORDMASKACCUM(sp),a5
    lea     ScreenRowByteBase+256(pc),a6
    clr.w   d0                      ; byte offset into FrameWordIndex

.m_loop:
    move.w  (a0),d1                 ; Cur.x (8.8)
    move.w  2(a0),d2                ; Cur.y (8.8)
    move.w  4(a0),d3                ; Cur.z (8.8)
    asr.w   #FP_SHIFT,d1            ; x integer
    asr.w   #FP_SHIFT,d2            ; y integer
    asr.w   #FP_SHIFT,d3            ; z integer

    movem.w (a1)+,d4-d6             ; Step.x / Step.y / Step.z
    add.w   d4,(a0)+
    add.w   d5,(a0)+
    add.w   d6,(a0)+

    move.l  a1,d6                   ; save next Step pointer, reuse A1 below

    move.b  0(a2,d1.w),d4           ; RotC[x]
    ext.w   d4
    move.b  0(a3,d3.w),d5           ; RotS[z]
    ext.w   d5
    add.w   d5,d4                   ; xr

    move.b  0(a2,d3.w),d5           ; RotC[z]
    ext.w   d5
    move.b  0(a3,d1.w),d1           ; RotS[x]
    ext.w   d1
    sub.w   d1,d5                   ; zr

    add.w   d5,d5
    add.w   d5,d5
    movea.l 0(a4,d5.w),a1           ; biased Proj row pointer

    move.b  0(a1,d4.w),d3           ; x projection already bias-adjusted
    ext.w   d3
    add.w   #CENTER_X,d3            ; px

    move.b  0(a1,d2.w),d4           ; y projection already bias-adjusted
    ext.w   d4
    add.w   d4,d4
    move.w  0(a6,d4.w),d2           ; row byte base

    move.w  d3,d1
    lsr.w   #4,d1                   ; px >> 4
    add.w   d1,d1                   ; row byte addend
    add.w   d1,d2                   ; byte offset into WordMaskAccum/Plane

    not.w   d3
    and.w   #15,d3
    moveq   #0,d5
    bset    d3,d5                   ; mask = 1 << (15 - (px & 15))

    move.w  0(a5,d2.w),d4
    bne.s   .m_have_word

    movea.l MARG_FRAMEWORDINDEX(sp),a1
    move.w  d2,0(a1,d0.w)
    addq.w  #2,d0

.m_have_word:
    or.w    d5,d4
    move.w  d4,0(a5,d2.w)

    movea.l d6,a1                   ; restore next Step pointer
    dbra    d7,.m_loop
    lsr.w   #1,d0
    bra.s   .m_done

.m_done_empty:
    clr.w   d0

.m_done:
    movem.l (sp)+,d2-d7/a2-a6
    rts

; ----------------------------------------------------------------------
; UWORD BuildStaticWordMaskFrameAsm(...)
; ----------------------------------------------------------------------

BuildStaticWordMaskFrameAsm:
_BuildStaticWordMaskFrameAsm:
    movem.l d2-d7/a2-a6,-(sp)

    movea.l SARG_POINTS(sp),a0
    move.l  SARG_POINTCOUNT(sp),d7
    beq.w   .s_done_empty

    subq.w  #1,d7
    movea.l SARG_ROTC(sp),a2
    movea.l SARG_ROTS(sp),a3
    movea.l SARG_PROJROWS(sp),a4
    movea.l SARG_WORDMASKACCUM(sp),a5
    lea     ScreenRowByteBase+256(pc),a6
    clr.w   d0                      ; byte offset into FrameWordIndex

.s_loop:
    move.b  (a0)+,d1                ; x
    ext.w   d1
    move.b  (a0)+,d2                ; y
    ext.w   d2
    move.b  (a0)+,d3                ; z
    ext.w   d3

    move.b  0(a2,d1.w),d4           ; RotC[x]
    ext.w   d4
    move.b  0(a3,d3.w),d5           ; RotS[z]
    ext.w   d5
    add.w   d5,d4                   ; xr

    move.b  0(a2,d3.w),d5           ; RotC[z]
    ext.w   d5
    move.b  0(a3,d1.w),d1           ; RotS[x]
    ext.w   d1
    sub.w   d1,d5                   ; zr

    add.w   d5,d5
    add.w   d5,d5
    movea.l 0(a4,d5.w),a1           ; biased Proj row pointer

    move.b  0(a1,d4.w),d3           ; x projection already bias-adjusted
    ext.w   d3
    add.w   #CENTER_X,d3            ; px

    move.b  0(a1,d2.w),d4           ; y projection already bias-adjusted
    ext.w   d4
    add.w   d4,d4
    move.w  0(a6,d4.w),d2           ; row byte base

    move.w  d3,d1
    lsr.w   #4,d1                   ; px >> 4
    add.w   d1,d1                   ; row byte addend
    add.w   d1,d2                   ; byte offset into WordMaskAccum/Plane

    not.w   d3
    and.w   #15,d3
    moveq   #0,d5
    bset    d3,d5                   ; mask = 1 << (15 - (px & 15))

    move.w  0(a5,d2.w),d4
    bne.s   .s_have_word

    movea.l SARG_FRAMEWORDINDEX(sp),a1
    move.w  d2,0(a1,d0.w)
    addq.w  #2,d0

.s_have_word:
    or.w    d5,d4
    move.w  d4,0(a5,d2.w)
    dbra    d7,.s_loop
    lsr.w   #1,d0
    bra.s   .s_done

.s_done_empty:
    clr.w   d0

.s_done:
    movem.l (sp)+,d2-d7/a2-a6
    rts

; ----------------------------------------------------------------------
; void UpdateFrameWordsAsm(...)
; ----------------------------------------------------------------------

UpdateFrameWordsAsm:
_UpdateFrameWordsAsm:
    movem.l d3-d7/a2-a5,-(sp)

    movea.l UARG_PLANE(sp),a0
    movea.l UARG_PREV(sp),a1
    movea.l a1,a2                   ; write pointer starts at PrevOffset base
    movea.l UARG_PREVCOUNT(sp),a3
    move.l  UARG_FRAMEWORDCOUNT(sp),d7
    movea.l UARG_WORDMASKACCUM(sp),a4
    movea.l UARG_FRAMEWORDINDEX(sp),a5
    clr.w   d6                      ; NewCount

    move.w  (a3),d5                 ; OldCount
    beq.w   .u_old_done
    subq.w  #1,d5

.u_old_loop:
    move.w  (a1)+,d0                ; byte offset

    move.w  0(a4,d0.w),d3           ; CurMask
    move.w  d3,0(a0,d0.w)           ; overwrite old plane word directly
    beq.s   .u_old_skip_store

    move.w  d0,(a2)+
    addq.w  #1,d6
    clr.w   0(a4,d0.w)

.u_old_skip_store:
    dbra    d5,.u_old_loop

.u_old_done:
    tst.l   d7
    beq.w   .u_done_store
    subq.w  #1,d7

.u_new_loop:
    move.w  (a5)+,d0                ; byte offset
    move.w  0(a4,d0.w),d3           ; CurMask
    beq.s   .u_new_skip

    move.w  d3,0(a0,d0.w)           ; new-only word, plane word is known zero
    move.w  d0,(a2)+
    addq.w  #1,d6
    clr.w   0(a4,d0.w)

.u_new_skip:
    dbra    d7,.u_new_loop

.u_done_store:
    move.w  d6,(a3)
    movem.l (sp)+,d3-d7/a2-a5
    rts

    even
ScreenRowByteBase:
    dc.w        0,   40,   80,  120,  160,  200,  240,  280
    dc.w      320,  360,  400,  440,  480,  520,  560,  600
    dc.w      640,  680,  720,  760,  800,  840,  880,  920
    dc.w      960, 1000, 1040, 1080, 1120, 1160, 1200, 1240
    dc.w     1280, 1320, 1360, 1400, 1440, 1480, 1520, 1560
    dc.w     1600, 1640, 1680, 1720, 1760, 1800, 1840, 1880
    dc.w     1920, 1960, 2000, 2040, 2080, 2120, 2160, 2200
    dc.w     2240, 2280, 2320, 2360, 2400, 2440, 2480, 2520
    dc.w     2560, 2600, 2640, 2680, 2720, 2760, 2800, 2840
    dc.w     2880, 2920, 2960, 3000, 3040, 3080, 3120, 3160
    dc.w     3200, 3240, 3280, 3320, 3360, 3400, 3440, 3480
    dc.w     3520, 3560, 3600, 3640, 3680, 3720, 3760, 3800
    dc.w     3840, 3880, 3920, 3960, 4000, 4040, 4080, 4120
    dc.w     4160, 4200, 4240, 4280, 4320, 4360, 4400, 4440
    dc.w     4480, 4520, 4560, 4600, 4640, 4680, 4720, 4760
    dc.w     4800, 4840, 4880, 4920, 4960, 5000, 5040, 5080
    dc.w     5120, 5160, 5200, 5240, 5280, 5320, 5360, 5400
    dc.w     5440, 5480, 5520, 5560, 5600, 5640, 5680, 5720
    dc.w     5760, 5800, 5840, 5880, 5920, 5960, 6000, 6040
    dc.w     6080, 6120, 6160, 6200, 6240, 6280, 6320, 6360
    dc.w     6400, 6440, 6480, 6520, 6560, 6600, 6640, 6680
    dc.w     6720, 6760, 6800, 6840, 6880, 6920, 6960, 7000
    dc.w     7040, 7080, 7120, 7160, 7200, 7240, 7280, 7320
    dc.w     7360, 7400, 7440, 7480, 7520, 7560, 7600, 7640
    dc.w     7680, 7720, 7760, 7800, 7840, 7880, 7920, 7960
    dc.w     8000, 8040, 8080, 8120, 8160, 8200, 8240, 8280
    dc.w     8320, 8360, 8400, 8440, 8480, 8520, 8560, 8600
    dc.w     8640, 8680, 8720, 8760, 8800, 8840, 8880, 8920
    dc.w     8960, 9000, 9040, 9080, 9120, 9160, 9200, 9240
    dc.w     9280, 9320, 9360, 9400, 9440, 9480, 9520, 9560
    dc.w     9600, 9640, 9680, 9720, 9760, 9800, 9840, 9880
    dc.w     9920, 9960,10000,10040,10080,10120,10160,10200
