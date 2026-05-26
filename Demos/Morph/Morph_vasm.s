; Morph point plotting hotpaths for Amiga 500 OCS / 68000
; vasm Motorola syntax

    machine 68000                                             ;assemble for Motorola 68000

MSAVE_SIZE          equ     44                                              ;saved regs for morph path: d2-d7/a2-a6
SSAVE_SIZE          equ     44                                              ;saved regs for static path: d2-d7/a2-a6
USAVE_SIZE          equ     36                                              ;saved regs for update path: d3-d7/a2-a5

MARG_CUR            equ     MSAVE_SIZE+4                                   ;arg 0: POINT3D16 *Cur
MARG_STEP           equ     MSAVE_SIZE+8                                   ;arg 1: const POINT3D16 *Step
MARG_POINTCOUNT     equ     MSAVE_SIZE+12                                  ;arg 2: ULONG PointCount
MARG_ROTC           equ     MSAVE_SIZE+16                                  ;arg 3: const BYTE *RotC (prebiased)
MARG_ROTS           equ     MSAVE_SIZE+20                                  ;arg 4: const BYTE *RotS (prebiased)
MARG_PROJROWS       equ     MSAVE_SIZE+24                                  ;arg 5: const BYTE *const *ProjRows (prebiased)
MARG_WORDMASKACCUM  equ     MSAVE_SIZE+28                                  ;arg 6: UWORD *WordMaskAccum
MARG_FRAMEWORDINDEX equ     MSAVE_SIZE+32                                  ;arg 7: UWORD *FrameWordIndex

SARG_POINTS         equ     SSAVE_SIZE+4                                   ;arg 0: const POINT3D8 *Points
SARG_POINTCOUNT     equ     SSAVE_SIZE+8                                   ;arg 1: ULONG PointCount
SARG_ROTC           equ     SSAVE_SIZE+12                                  ;arg 2: const BYTE *RotC (prebiased)
SARG_ROTS           equ     SSAVE_SIZE+16                                  ;arg 3: const BYTE *RotS (prebiased)
SARG_PROJROWS       equ     SSAVE_SIZE+20                                  ;arg 4: const BYTE *const *ProjRows (prebiased)
SARG_WORDMASKACCUM  equ     SSAVE_SIZE+24                                  ;arg 5: UWORD *WordMaskAccum
SARG_FRAMEWORDINDEX equ     SSAVE_SIZE+28                                  ;arg 6: UWORD *FrameWordIndex

UARG_PLANE          equ     USAVE_SIZE+4                                   ;arg 0: UWORD *Plane
UARG_PREV           equ     USAVE_SIZE+8                                   ;arg 1: UWORD *PrevOffsets
UARG_PREVCOUNT      equ     USAVE_SIZE+12                                  ;arg 2: UWORD *PrevCount
UARG_FRAMEWORDCOUNT equ     USAVE_SIZE+16                                  ;arg 3: ULONG FrameWordCount
UARG_WORDMASKACCUM  equ     USAVE_SIZE+20                                  ;arg 4: UWORD *WordMaskAccum
UARG_FRAMEWORDINDEX equ     USAVE_SIZE+24                                  ;arg 5: const UWORD *FrameWordIndex

CENTER_X            equ     160                                             ;horizontal projection center in pixels
CENTER_Y            equ     128                                             ;vertical projection center in pixels
FP_SHIFT            equ     8                                               ;8.8 fixed-point fractional shift

CUSTOMREGS          equ     $00DFF000                                      ;custom chip register base
DMACONR             equ     $00DFF002                                      ;DMA control read register
BLTCON0             equ     $00DFF040                                      ;blitter control register 0
BLTCON1             equ     $00DFF042                                      ;blitter control register 1
BLTAFWM             equ     $00DFF044                                      ;blitter first word mask A
BLTALWM             equ     $00DFF046                                      ;blitter last word mask A
BLTCPTH             equ     $00DFF048                                      ;blitter C pointer high word
BLTAPTL             equ     $00DFF052                                      ;blitter A pointer low / line accumulator
BLTDPTH             equ     $00DFF054                                      ;blitter D pointer high word
BLTSIZE             equ     $00DFF058                                      ;blitter size/start register
BLTBMOD             equ     $00DFF062                                      ;blitter B modulo / line increment
BLTAMOD             equ     $00DFF064                                      ;blitter A modulo / line decrement
BLTCMOD             equ     $00DFF060                                      ;blitter C modulo
BLTDMOD             equ     $00DFF066                                      ;blitter D modulo
BLTBDAT             equ     $00DFF072                                      ;blitter B data / line texture
BLTADAT             equ     $00DFF074                                      ;blitter A data / line brush
DMAB_BLITTER        equ     6                                               ;blitter busy flag bit
BYTES_PER_ROW       equ     40                                              ;1bpl screen row stride
CLEAR_BLTSIZE       equ     $4014                                           ;256 rows, 20 words per row
WIRE_CLEAR_OFFSET   equ     964                                             ;24 rows * 40 + 2 words * 2
WIRE_CLEAR_BLTSIZE  equ     $3410                                           ;208 rows, 16 words per row
WIRE_CLEAR_MOD      equ     8                                               ;skip four words outside the clear rectangle
OCTA_EDGE_COUNT     equ     12                                              ;fixed octahedron edge count

_BuildMorphWordMaskFrameAdvanceAsm::                         ;public symbol with underscore
    movem.l d2-d7/a2-a6,-(sp)                               ;save all non-result registers used by this routine

    movea.l MARG_CUR(sp),a0                                ;a0 = Cur pointer
    movea.l MARG_STEP(sp),a1                               ;a1 = Step pointer
    move.l  MARG_POINTCOUNT(sp),d7                         ;d7 = number of points
    beq.w   .m_done_empty                                  ;return 0 immediately when no points are present

    subq.w  #1,d7                                         ;convert count into DBRA loop counter
    movea.l MARG_ROTC(sp),a2                               ;a2 = RotC lookup base
    movea.l MARG_ROTS(sp),a3                               ;a3 = RotS lookup base
    movea.l MARG_PROJROWS(sp),a4                           ;a4 = ProjRows pointer table base
    movea.l MARG_WORDMASKACCUM(sp),a5                      ;a5 = word mask accumulator base
    lea     ScreenRowByteBase+256(pc),a6                   ;a6 = row-base table centered around projected Y = 0
    clr.w   d0                                            ;d0 = byte cursor into FrameWordIndex list

.m_loop:                                                  ;process one morph point
    move.w  (a0),d1                                       ;d1 = Cur.x in 8.8 fixed point
    move.w  2(a0),d2                                      ;d2 = Cur.y in 8.8 fixed point
    move.w  4(a0),d3                                      ;d3 = Cur.z in 8.8 fixed point
    asr.w   #FP_SHIFT,d1                                  ;convert Cur.x to signed integer x
    asr.w   #FP_SHIFT,d2                                  ;convert Cur.y to signed integer y
    asr.w   #FP_SHIFT,d3                                  ;convert Cur.z to signed integer z

    movem.w (a1)+,d4-d6                                   ;d4/d5/d6 = Step.x / Step.y / Step.z
    add.w   d4,(a0)+                                      ;Cur.x += Step.x and advance Cur pointer to y
    add.w   d5,(a0)+                                      ;Cur.y += Step.y and advance Cur pointer to z
    add.w   d6,(a0)+                                      ;Cur.z += Step.z and advance Cur pointer to next point

    move.l  a1,d6                                         ;save the advanced Step pointer in d6 so a1 can be reused

    move.b  0(a2,d1.w),d4                                 ;d4 = RotC[x]
    ext.w   d4                                            ;sign-extend rotation lookup to word
    move.b  0(a3,d3.w),d5                                 ;d5 = RotS[z]
    ext.w   d5                                            ;sign-extend rotation lookup to word
    add.w   d5,d4                                         ;d4 = xr = RotC[x] + RotS[z]

    move.b  0(a2,d3.w),d5                                 ;d5 = RotC[z]
    ext.w   d5                                            ;sign-extend rotation lookup to word
    move.b  0(a3,d1.w),d1                                 ;d1 = RotS[x]
    ext.w   d1                                            ;sign-extend rotation lookup to word
    sub.w   d1,d5                                         ;d5 = zr = RotC[z] - RotS[x]

    add.w   d5,d5                                         ;scale zr by 2 for pointer-sized indexing
    add.w   d5,d5                                         ;scale zr by 4 because ProjRows contains long pointers
    movea.l 0(a4,d5.w),a1                                 ;a1 = ProjRows[zr], already biased for projection X/Y lookup

    move.b  0(a1,d4.w),d3                                 ;d3 = projected X offset, already bias-adjusted
    ext.w   d3                                            ;sign-extend projected X to word
    add.w   #CENTER_X,d3                                  ;d3 = final screen X in pixels

    move.b  0(a1,d2.w),d4                                 ;d4 = projected Y offset, already bias-adjusted
    ext.w   d4                                            ;sign-extend projected Y to word
    add.w   d4,d4                                         ;scale projected Y by 2 for word lookup
    move.w  0(a6,d4.w),d2                                 ;d2 = byte offset of the destination row within the bitplane

    move.w  d3,d1                                         ;copy screen X so we can derive the destination word index
    lsr.w   #4,d1                                         ;d1 = screen X / 16 = word column
    add.w   d1,d1                                         ;scale word column by 2 because offsets are stored in bytes
    add.w   d1,d2                                         ;d2 = final byte offset of the destination word

    not.w   d3                                            ;invert X so low nibble becomes bit position from the left
    and.w   #15,d3                                        ;keep only the intra-word bit index 0..15
    clr.w   d5                                            ;clear destination mask
    bset    d3,d5                                         ;set one bit in the destination word mask

    move.w  0(a5,d2.w),d4                                 ;d4 = current accumulated mask for this destination word
    bne.s   .m_have_word                                  ;skip list insertion if this word was already touched

    movea.l MARG_FRAMEWORDINDEX(sp),a1                    ;a1 = unique-word list base
    move.w  d2,0(a1,d0.w)                                 ;store the new touched word byte offset
    addq.w  #2,d0                                         ;advance unique-word list cursor to the next slot

.m_have_word:                                             ;merge the point bit into the destination word mask
    or.w    d5,d4                                         ;add this pixel bit to the accumulated mask
    move.w  d4,0(a5,d2.w)                                 ;write the updated mask back to the accumulator

    movea.l d6,a1                                         ;restore the advanced Step pointer for the next iteration
    dbra    d7,.m_loop                                    ;continue until all points have been processed
    lsr.w   #1,d0                                         ;convert byte cursor into word count for the return value
    bra.s   .m_done                                       ;leave through the common exit path

.m_done_empty:                                            ;special case for PointCount == 0
    clr.w   d0                                            ;return 0 touched words

.m_done:                                                  ;common function exit
    movem.l (sp)+,d2-d7/a2-a6                             ;restore saved registers
    rts                                                   ;return with d0.w = unique touched word count

_BuildStaticWordMaskFrameAsm::	;public symbol with underscore
    movem.l d2-d7/a2-a6,-(sp)	;save all non-result registers used by this routine

    movea.l SARG_POINTS(sp),a0	;a0 = packed POINT3D8 source pointer
    move.l  SARG_POINTCOUNT(sp),d7	;d7 = number of points
    beq.w   .s_done_empty	;return 0 immediately when no points are present

    subq.w  #1,d7	;convert count into DBRA loop counter
    movea.l SARG_ROTC(sp),a2	;a2 = RotC lookup base
    movea.l SARG_ROTS(sp),a3	;a3 = RotS lookup base
    movea.l SARG_PROJROWS(sp),a4	;a4 = ProjRows pointer table base
    movea.l SARG_WORDMASKACCUM(sp),a5	;a5 = word mask accumulator base
    lea     ScreenRowByteBase+256(pc),a6	;a6 = row-base table centered around projected Y = 0
    clr.w   d0	;d0 = byte cursor into FrameWordIndex list

.s_loop:	;process one static point
    move.b  (a0)+,d1	;d1 = source x as signed byte
    ext.w   d1	;sign-extend x to word
    move.b  (a0)+,d2	;d2 = source y as signed byte
    ext.w   d2	;sign-extend y to word
    move.b  (a0)+,d3	;d3 = source z as signed byte
    ext.w   d3	;sign-extend z to word

    move.b  0(a2,d1.w),d4	;d4 = RotC[x]
    ext.w   d4	;sign-extend rotation lookup to word
    move.b  0(a3,d3.w),d5	;d5 = RotS[z]
    ext.w   d5	;sign-extend rotation lookup to word
    add.w   d5,d4	;d4 = xr = RotC[x] + RotS[z]

    move.b  0(a2,d3.w),d5	;d5 = RotC[z]
    ext.w   d5	;sign-extend rotation lookup to word
    move.b  0(a3,d1.w),d1	;d1 = RotS[x]
    ext.w   d1	;sign-extend rotation lookup to word
    sub.w   d1,d5	;d5 = zr = RotC[z] - RotS[x]

    add.w   d5,d5	;scale zr by 2 for pointer-sized indexing
    add.w   d5,d5	;scale zr by 4 because ProjRows contains long pointers
    movea.l 0(a4,d5.w),a1	;a1 = ProjRows[zr], already biased for projection X/Y lookup

    move.b  0(a1,d4.w),d3	;d3 = projected X offset, already bias-adjusted
    ext.w   d3	;sign-extend projected X to word
    add.w   #CENTER_X,d3	;d3 = final screen X in pixels

    move.b  0(a1,d2.w),d4	;d4 = projected Y offset, already bias-adjusted
    ext.w   d4	;sign-extend projected Y to word
    add.w   d4,d4	;scale projected Y by 2 for word lookup
    move.w  0(a6,d4.w),d2	;d2 = byte offset of the destination row within the bitplane

    move.w  d3,d1	;copy screen X so we can derive the destination word index
    lsr.w   #4,d1	;d1 = screen X / 16 = word column
    add.w   d1,d1	;scale word column by 2 because offsets are stored in bytes
    add.w   d1,d2	;d2 = final byte offset of the destination word

    not.w   d3	;invert X so low nibble becomes bit position from the left
    and.w   #15,d3	;keep only the intra-word bit index 0..15
    clr.w   d5	;clear destination mask
    bset    d3,d5	;set one bit in the destination word mask

    move.w  0(a5,d2.w),d4	;d4 = current accumulated mask for this destination word
    bne.s   .s_have_word	;skip list insertion if this word was already touched

    movea.l SARG_FRAMEWORDINDEX(sp),a1	;a1 = unique-word list base
    move.w  d2,0(a1,d0.w)	;store the new touched word byte offset
    addq.w  #2,d0	;advance unique-word list cursor to the next slot

.s_have_word:	;merge the point bit into the destination word mask
    or.w    d5,d4	;add this pixel bit to the accumulated mask
    move.w  d4,0(a5,d2.w)	;write the updated mask back to the accumulator
    dbra    d7,.s_loop	;continue until all static points have been processed
    lsr.w   #1,d0	;convert byte cursor into word count for the return value
    bra.s   .s_done	;leave through the common exit path

.s_done_empty:	;special case for PointCount == 0
    clr.w   d0	;return 0 touched words

.s_done:	;common function exit
    movem.l (sp)+,d2-d7/a2-a6	;restore saved registers
    rts	;return with d0.w = unique touched word count

_UpdateFrameWordsAsm::	;public symbol with underscore
    movem.l d3-d7/a2-a5,-(sp)	;save all caller-visible registers used by this routine

    movea.l UARG_PLANE(sp),a0	;a0 = destination plane base
    movea.l UARG_PREV(sp),a1	;a1 = read pointer for previous offsets
    movea.l a1,a2	;a2 = write pointer for the next previous-offset list
    movea.l UARG_PREVCOUNT(sp),a3	;a3 = address of stored previous-count value
    move.l  UARG_FRAMEWORDCOUNT(sp),d7	;d7 = current frame word count
    movea.l UARG_WORDMASKACCUM(sp),a4	;a4 = sparse word mask accumulator base
    movea.l UARG_FRAMEWORDINDEX(sp),a5	;a5 = current frame touched-word list
    clr.w   d6	;d6 = NewCount = 0

    move.w  (a3),d5	;d5 = OldCount from the previous frame
    beq.w   .u_old_done	;skip old-word processing if no old words exist
    subq.w  #1,d5	;convert old count into DBRA loop counter

.u_old_loop:	;walk all words touched in the previous frame
    move.w  (a1)+,d0	;d0 = byte offset of one previously touched word

    move.w  0(a4,d0.w),d3	;d3 = current frame mask for that word, if any
    move.w  d3,0(a0,d0.w)	;overwrite the plane word directly with the current mask
    beq.s   .u_old_skip_store	;if current mask is zero, do not keep this word in the new list

    move.w  d0,(a2)+	;store surviving offset into the next Prev list
    addq.w  #1,d6	;increment the new previous-word count
    clr.w   0(a4,d0.w)	;clear the accumulator entry now that it was consumed

.u_old_skip_store:	;continue with the next old offset
    dbra    d5,.u_old_loop	;loop until every old word has been rewritten

.u_old_done:	;old-word rewrite pass is complete
    tst.l   d7	;check whether the current frame has any touched words at all
    beq.w   .u_done_store	;if not, we can store the new count and return
    subq.w  #1,d7	;convert current frame count into DBRA loop counter

.u_new_loop:	;walk words touched in the current frame but not seen in old pass
    move.w  (a5)+,d0	;d0 = byte offset of one currently touched word
    move.w  0(a4,d0.w),d3	;d3 = current frame mask for that word
    beq.s   .u_new_skip	;skip if the old pass already consumed and cleared this word

    move.w  d3,0(a0,d0.w)	;write the new word directly, plane contents are known zero here
    move.w  d0,(a2)+	;append the offset to the next Prev list
    addq.w  #1,d6	;increment the new previous-word count
    clr.w   0(a4,d0.w)	;clear the accumulator entry now that it was consumed

.u_new_skip:	;continue with the next current-frame offset
    dbra    d7,.u_new_loop	;loop until every current-frame word has been visited

.u_done_store:	;finalize the new previous-word metadata
    move.w  d6,(a3)	;store NewCount so the next frame can reuse it
    movem.l (sp)+,d3-d7/a2-a5	;restore saved registers
    rts	;return to the C caller

_WaitLocalBlitter:
    lea     CUSTOMREGS,a1	;load custom chip base
.w_wait:
    btst.b  #DMAB_BLITTER,(DMACONR-CUSTOMREGS,a1)	;test blitter busy bit
    bne.s   .w_wait	;wait until blitter is idle
    rts	;return with a1 = CUSTOMREGS

_BlitClearPlaneAsm::
    bsr.s   _WaitLocalBlitter	;wait before touching blitter registers
    move.l  #$01000000,(BLTCON0-CUSTOMREGS,a1)	;enable D only and clear via zero minterm
    clr.w   (BLTDMOD-CUSTOMREGS,a1)	;contiguous destination
    move.l  a0,(BLTDPTH-CUSTOMREGS,a1)	;set destination plane pointer
    move.w  #CLEAR_BLTSIZE,(BLTSIZE-CUSTOMREGS,a1)	;start full 1bpl clear
    rts	;return while clear runs

_BlitClearWireRectAsm::
    bsr.s   _WaitLocalBlitter	;wait before touching blitter registers
    move.l  #$01000000,(BLTCON0-CUSTOMREGS,a1)	;enable D only and clear via zero minterm
    move.w  #WIRE_CLEAR_MOD,(BLTDMOD-CUSTOMREGS,a1)	;skip untouched words at line end
    adda.w  #WIRE_CLEAR_OFFSET,a0	;move to fixed wireframe clear rectangle
    move.l  a0,(BLTDPTH-CUSTOMREGS,a1)	;set destination rectangle pointer
    move.w  #WIRE_CLEAR_BLTSIZE,(BLTSIZE-CUSTOMREGS,a1)	;start rectangle clear
    rts	;return while clear runs


_DrawBlitterLinesAsm::
    movem.l d2-d7/a2-a6,-(sp)	;save registers used by batch line renderer
    movea.l a0,a4	;save plane base for all lines
    movea.l a1,a5	;save projected vertex array
    movea.l a2,a6	;save edge index array
    lea     ScreenRowByteBase(pc),a3	;a3 = row offset table
    bsr     _WaitLocalBlitter	;wait once before common blitter setup
    move.w  #$FFFF,(BLTAFWM-CUSTOMREGS,a1)	;line-mode first word mask
    move.w  #$FFFF,(BLTALWM-CUSTOMREGS,a1)	;line-mode last word mask
    move.w  #$8000,(BLTADAT-CUSTOMREGS,a1)	;one-pixel line brush
    move.w  #$FFFF,(BLTBDAT-CUSTOMREGS,a1)	;solid line texture
    move.w  #BYTES_PER_ROW,(BLTCMOD-CUSTOMREGS,a1)	;C modulo = screen stride
    move.w  #BYTES_PER_ROW,(BLTDMOD-CUSTOMREGS,a1)	;D modulo = screen stride

    moveq   #OCTA_EDGE_COUNT-1,d7	;d7 = fixed DBRA edge counter
.dl_loop:
    move.w  d7,-(sp)	;save DBRA counter while d7 is used by line setup

    moveq   #0,d4	;clear first vertex index
    move.b  (a6)+,d4	;d4 = edge.a
    lsl.w   #2,d4	;POINT2D is 4 bytes
    moveq   #0,d5	;clear second vertex index
    move.b  (a6)+,d5	;d5 = edge.b
    lsl.w   #2,d5	;POINT2D is 4 bytes
    move.w  0(a5,d4.w),d0	;d0 = x0
    move.w  2(a5,d4.w),d1	;d1 = y0
    move.w  0(a5,d5.w),d2	;d2 = x1
    move.w  2(a5,d5.w),d3	;d3 = y1

    move.w  d0,d4	;d4 = x0
    move.w  d1,d5	;d5 = y0
    move.w  d2,d6	;d6 = x1
    move.w  d3,d7	;d7 = y1

    move.w  d6,d0	;d0 = x1
    sub.w   d4,d0	;d0 = signed dx
    move.w  d7,d1	;d1 = y1
    sub.w   d5,d1	;d1 = signed dy
    moveq   #1,d2	;d2 = BLTCON1 with LINE bit set

    move.w  d0,d6	;d6 = abs dx candidate
    bpl.s   .dx_pos	;skip when dx is positive
    neg.w   d6	;make abs dx
.dx_pos:
    move.w  d1,d7	;d7 = abs dy candidate
    bpl.s   .dy_pos	;skip when dy is positive
    neg.w   d7	;make abs dy
.dy_pos:
    cmp.w   d6,d7	;compare abs dy with abs dx
    ble.s   .major_x	;use x as major axis when abs dy <= abs dx
    exg     d0,d1	;swap signed deltas so d0 is major and d1 is minor
    bra.s   .normalise	;continue with octant setup
.major_x:
    ori.w   #$0010,d2	;set SUD for x-major lines
.normalise:
    tst.w   d1	;test signed minor delta
    bpl.s   .minor_pos	;skip if minor direction is positive
    ori.w   #$0008,d2	;set SUL for negative minor direction
    neg.w   d1	;make minor delta positive
.minor_pos:
    tst.w   d0	;test signed major delta
    bpl.s   .major_pos	;skip if major direction is positive
    ori.w   #$0004,d2	;set AUL for negative major direction
    neg.w   d0	;make major delta positive
.major_pos:

    move.w  d1,d3	;d3 = minor delta
    lsl.w   #2,d3	;d3 = 4 * minor delta
    move.w  d0,d6	;d6 = major delta
    add.w   d6,d6	;d6 = 2 * major delta
    sub.w   d6,d3	;d3 = initial accumulator = 4dy - 2dx
    bpl.s   .acc_pos	;skip sign flag when accumulator is positive
    ori.w   #$0040,d2	;set SIGN bit for negative initial accumulator
.acc_pos:

    move.w  d1,d6	;d6 = minor delta
    lsl.w   #2,d6	;d6 = BLTBMOD = 4dy
    move.w  d1,d7	;d7 = minor delta
    sub.w   d0,d7	;d7 = dy - dx
    lsl.w   #2,d7	;d7 = BLTAMOD = 4(dy - dx)

    move.w  d4,d1	;d1 = x0
    and.w   #15,d1	;d1 = x0 & 15
    lsl.w   #4,d1	;move shift nibble toward bits 15..12
    lsl.w   #4,d1	;move shift nibble toward bits 15..12
    lsl.w   #4,d1	;move shift nibble into bits 15..12
    ori.w   #$0BCA,d1	;USEA/USEC/USED with normal line minterm

    addq.w  #1,d0	;line height = major length + 1
    lsl.w   #6,d0	;move height into BLTSIZE high field
    ori.w   #2,d0	;line mode requires width field = 2

    add.w   d5,d5	;scale y0 for row table lookup
    move.w  0(a3,d5.w),d5	;d5 = y0 * 40
    lsr.w   #4,d4	;d4 = x0 / 16
    add.w   d4,d4	;scale word column to bytes
    add.w   d4,d5	;d5 = start byte offset
    movea.l a4,a2	;a2 = plane base
    adda.w  d5,a2	;a2 = first destination word address

    bsr     _WaitLocalBlitter	;wait after CPU setup so calculation overlaps previous blit
    move.w  d1,(BLTCON0-CUSTOMREGS,a1)	;set source shift, channels, and minterm
    move.w  d2,(BLTCON1-CUSTOMREGS,a1)	;set octant, sign, and line mode
    move.w  d3,(BLTAPTL-CUSTOMREGS,a1)	;set initial line accumulator
    move.w  d6,(BLTBMOD-CUSTOMREGS,a1)	;set accumulator increment
    move.w  d7,(BLTAMOD-CUSTOMREGS,a1)	;set accumulator decrement
    move.l  a2,(BLTCPTH-CUSTOMREGS,a1)	;set C pointer to destination word
    move.l  a2,(BLTDPTH-CUSTOMREGS,a1)	;set D pointer to destination word
    move.w  d0,(BLTSIZE-CUSTOMREGS,a1)	;start line blit

    move.w  (sp)+,d7	;restore DBRA counter
    dbra    d7,.dl_loop	;draw all edges
    bsr     _WaitLocalBlitter	;wait until final line finished before buffer is displayed
.dl_done:
    movem.l (sp)+,d2-d7/a2-a6	;restore saved registers
    rts	;return to caller

    even	;align the following tables on an even address

ScreenRowByteBase:	;256-entry table of row byte bases: y -> y * 40
    dc.w        0,   40,   80,  120,  160,  200,  240,  280	;rows 0..7
    dc.w      320,  360,  400,  440,  480,  520,  560,  600	;rows 8..15
    dc.w      640,  680,  720,  760,  800,  840,  880,  920	;rows 16..23
    dc.w      960, 1000, 1040, 1080, 1120, 1160, 1200, 1240	;rows 24..31
    dc.w     1280, 1320, 1360, 1400, 1440, 1480, 1520, 1560	;rows 32..39
    dc.w     1600, 1640, 1680, 1720, 1760, 1800, 1840, 1880	;rows 40..47
    dc.w     1920, 1960, 2000, 2040, 2080, 2120, 2160, 2200	;rows 48..55
    dc.w     2240, 2280, 2320, 2360, 2400, 2440, 2480, 2520	;rows 56..63
    dc.w     2560, 2600, 2640, 2680, 2720, 2760, 2800, 2840	;rows 64..71
    dc.w     2880, 2920, 2960, 3000, 3040, 3080, 3120, 3160	;rows 72..79
    dc.w     3200, 3240, 3280, 3320, 3360, 3400, 3440, 3480	;rows 80..87
    dc.w     3520, 3560, 3600, 3640, 3680, 3720, 3760, 3800	;rows 88..95
    dc.w     3840, 3880, 3920, 3960, 4000, 4040, 4080, 4120	;rows 96..103
    dc.w     4160, 4200, 4240, 4280, 4320, 4360, 4400, 4440	;rows 104..111
    dc.w     4480, 4520, 4560, 4600, 4640, 4680, 4720, 4760	;rows 112..119
    dc.w     4800, 4840, 4880, 4920, 4960, 5000, 5040, 5080	;rows 120..127
    dc.w     5120, 5160, 5200, 5240, 5280, 5320, 5360, 5400	;rows 128..135
    dc.w     5440, 5480, 5520, 5560, 5600, 5640, 5680, 5720	;rows 136..143
    dc.w     5760, 5800, 5840, 5880, 5920, 5960, 6000, 6040	;rows 144..151
    dc.w     6080, 6120, 6160, 6200, 6240, 6280, 6320, 6360	;rows 152..159
    dc.w     6400, 6440, 6480, 6520, 6560, 6600, 6640, 6680	;rows 160..167
    dc.w     6720, 6760, 6800, 6840, 6880, 6920, 6960, 7000	;rows 168..175
    dc.w     7040, 7080, 7120, 7160, 7200, 7240, 7280, 7320	;rows 176..183
    dc.w     7360, 7400, 7440, 7480, 7520, 7560, 7600, 7640	;rows 184..191
    dc.w     7680, 7720, 7760, 7800, 7840, 7880, 7920, 7960	;rows 192..199
    dc.w     8000, 8040, 8080, 8120, 8160, 8200, 8240, 8280	;rows 200..207
    dc.w     8320, 8360, 8400, 8440, 8480, 8520, 8560, 8600	;rows 208..215
    dc.w     8640, 8680, 8720, 8760, 8800, 8840, 8880, 8920	;rows 216..223
    dc.w     8960, 9000, 9040, 9080, 9120, 9160, 9200, 9240	;rows 224..231
    dc.w     9280, 9320, 9360, 9400, 9440, 9480, 9520, 9560	;rows 232..239
    dc.w     9600, 9640, 9680, 9720, 9760, 9800, 9840, 9880	;rows 240..247
    dc.w     9920, 9960,10000,10040,10080,10120,10160,10200	;rows 248..255
