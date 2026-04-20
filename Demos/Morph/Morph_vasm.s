; -----------------------------------------------------------------------------
; Morph point plotting hotpaths
; Amiga 500 OCS / 68000 - vasm Motorola syntax
;
; Key idea
; --------
; The C side prepares prebiased lookup bases so the inner loops can avoid most
; constant offset arithmetic:
;   RotC / RotS     -> base + SRC_COORD_BIAS
;   ProjRows        -> base + (Z_OFFSET - PROJ_Z_MIN)
;   each ProjRows[] -> row start + PROJ_COORD_BIAS
;
; This asm file adds one more lookup:
;   ScreenRowByteBase[y] = y * 40
;
;
; BuildMorphWordMaskFrameAdvanceAsm
; ---------------------------------
; Processes the active morph state in 8.8 fixed point, advances Cur by Step,
; projects each point, and builds the unique-word list for the frame.
;
; BuildStaticWordMaskFrameAsm
; ---------------------------
; Does the same work for packed static points stored as signed bytes.
;
; UpdateFrameWordsAsm
; -------------------
; Rewrites only the words touched by the previous and current frame.
;
; Projection assumptions
; ----------------------
;   FP_SHIFT                = 8
;   CENTER_X / CENTER_Y     = 160 / 128
;   SCREEN_WORDS_PER_ROW    = 20
;
; Additional assumptions
; ----------------------
;   - POINT3D8 is a packed 3-byte struct on the C side.
;   - Projected Y is used around CENTER_Y with a base of table + 256 bytes.
;
; -----------------------------------------------------------------------------

    machine 68000                                ; assemble for Motorola 68000

MSAVE_SIZE          equ     44                   ; saved regs for morph path: d2-d7/a2-a6
SSAVE_SIZE          equ     44                   ; saved regs for static path: d2-d7/a2-a6
USAVE_SIZE          equ     36                   ; saved regs for update path: d3-d7/a2-a5

MARG_CUR            equ     MSAVE_SIZE+4         ; arg 0: POINT3D16 *Cur
MARG_STEP           equ     MSAVE_SIZE+8         ; arg 1: const POINT3D16 *Step
MARG_POINTCOUNT     equ     MSAVE_SIZE+12        ; arg 2: ULONG PointCount
MARG_ROTC           equ     MSAVE_SIZE+16        ; arg 3: const BYTE *RotC (prebiased)
MARG_ROTS           equ     MSAVE_SIZE+20        ; arg 4: const BYTE *RotS (prebiased)
MARG_PROJROWS       equ     MSAVE_SIZE+24        ; arg 5: const BYTE *const *ProjRows (prebiased)
MARG_WORDMASKACCUM  equ     MSAVE_SIZE+28        ; arg 6: UWORD *WordMaskAccum
MARG_FRAMEWORDINDEX equ     MSAVE_SIZE+32        ; arg 7: UWORD *FrameWordIndex

SARG_POINTS         equ     SSAVE_SIZE+4         ; arg 0: const POINT3D8 *Points
SARG_POINTCOUNT     equ     SSAVE_SIZE+8         ; arg 1: ULONG PointCount
SARG_ROTC           equ     SSAVE_SIZE+12        ; arg 2: const BYTE *RotC (prebiased)
SARG_ROTS           equ     SSAVE_SIZE+16        ; arg 3: const BYTE *RotS (prebiased)
SARG_PROJROWS       equ     SSAVE_SIZE+20        ; arg 4: const BYTE *const *ProjRows (prebiased)
SARG_WORDMASKACCUM  equ     SSAVE_SIZE+24        ; arg 5: UWORD *WordMaskAccum
SARG_FRAMEWORDINDEX equ     SSAVE_SIZE+28        ; arg 6: UWORD *FrameWordIndex

UARG_PLANE          equ     USAVE_SIZE+4         ; arg 0: UWORD *Plane
UARG_PREV           equ     USAVE_SIZE+8         ; arg 1: UWORD *PrevOffsets
UARG_PREVCOUNT      equ     USAVE_SIZE+12        ; arg 2: UWORD *PrevCount
UARG_FRAMEWORDCOUNT equ     USAVE_SIZE+16        ; arg 3: ULONG FrameWordCount
UARG_WORDMASKACCUM  equ     USAVE_SIZE+20        ; arg 4: UWORD *WordMaskAccum
UARG_FRAMEWORDINDEX equ     USAVE_SIZE+24        ; arg 5: const UWORD *FrameWordIndex

CENTER_X            equ     160                  ; horizontal projection center in pixels
CENTER_Y            equ     128                  ; vertical projection center in pixels
FP_SHIFT            equ     8                    ; 8.8 fixed-point fractional shift

; -----------------------------------------------------------------------------
; UWORD BuildMorphWordMaskFrameAdvanceAsm(...)
;
; Input:
;   Cur            = current morph points in 8.8 fixed point
;   Step           = per-point 8.8 fixed-point delta
;   PointCount     = number of points to process
;   RotC / RotS    = prebiased rotation lookup bases
;   ProjRows       = prebiased perspective row table base
;   WordMaskAccum  = per-frame sparse word mask buffer
;   FrameWordIndex = list of unique touched word offsets
;
; Output:
;   d0.w = number of unique words touched this frame
;
; Clobbers:
;   d0-d7/a0-a6 (preserved for caller via movem except d0 result)
; -----------------------------------------------------------------------------

_BuildMorphWordMaskFrameAdvanceAsm::             ; public symbol with underscore
    movem.l d2-d7/a2-a6,-(sp)                    ; save all non-result registers used by this routine

    movea.l MARG_CUR(sp),a0                      ; a0 = Cur pointer
    movea.l MARG_STEP(sp),a1                     ; a1 = Step pointer
    move.l  MARG_POINTCOUNT(sp),d7               ; d7 = number of points
    beq.w   .m_done_empty                        ; return 0 immediately when no points are present

    subq.w  #1,d7                                ; convert count into DBRA loop counter
    movea.l MARG_ROTC(sp),a2                     ; a2 = RotC lookup base
    movea.l MARG_ROTS(sp),a3                     ; a3 = RotS lookup base
    movea.l MARG_PROJROWS(sp),a4                 ; a4 = ProjRows pointer table base
    movea.l MARG_WORDMASKACCUM(sp),a5            ; a5 = word mask accumulator base
    lea     ScreenRowByteBase+256(pc),a6         ; a6 = row-base table centered around projected Y = 0
    clr.w   d0                                   ; d0 = byte cursor into FrameWordIndex list

.m_loop:                                         ; process one morph point
    move.w  (a0),d1                              ; d1 = Cur.x in 8.8 fixed point
    move.w  2(a0),d2                             ; d2 = Cur.y in 8.8 fixed point
    move.w  4(a0),d3                             ; d3 = Cur.z in 8.8 fixed point
    asr.w   #FP_SHIFT,d1                         ; convert Cur.x to signed integer x
    asr.w   #FP_SHIFT,d2                         ; convert Cur.y to signed integer y
    asr.w   #FP_SHIFT,d3                         ; convert Cur.z to signed integer z

    movem.w (a1)+,d4-d6                          ; d4/d5/d6 = Step.x / Step.y / Step.z
    add.w   d4,(a0)+                             ; Cur.x += Step.x and advance Cur pointer to y
    add.w   d5,(a0)+                             ; Cur.y += Step.y and advance Cur pointer to z
    add.w   d6,(a0)+                             ; Cur.z += Step.z and advance Cur pointer to next point

    move.l  a1,d6                                ; save the advanced Step pointer in d6 so a1 can be reused

    move.b  0(a2,d1.w),d4                        ; d4 = RotC[x]
    ext.w   d4                                   ; sign-extend rotation lookup to word
    move.b  0(a3,d3.w),d5                        ; d5 = RotS[z]
    ext.w   d5                                   ; sign-extend rotation lookup to word
    add.w   d5,d4                                ; d4 = xr = RotC[x] + RotS[z]

    move.b  0(a2,d3.w),d5                        ; d5 = RotC[z]
    ext.w   d5                                   ; sign-extend rotation lookup to word
    move.b  0(a3,d1.w),d1                        ; d1 = RotS[x]
    ext.w   d1                                   ; sign-extend rotation lookup to word
    sub.w   d1,d5                                ; d5 = zr = RotC[z] - RotS[x]

    add.w   d5,d5                                ; scale zr by 2 for pointer-sized indexing
    add.w   d5,d5                                ; scale zr by 4 because ProjRows contains long pointers
    movea.l 0(a4,d5.w),a1                        ; a1 = ProjRows[zr], already biased for projection X/Y lookup

    move.b  0(a1,d4.w),d3                        ; d3 = projected X offset, already bias-adjusted
    ext.w   d3                                   ; sign-extend projected X to word
    add.w   #CENTER_X,d3                         ; d3 = final screen X in pixels

    move.b  0(a1,d2.w),d4                        ; d4 = projected Y offset, already bias-adjusted
    ext.w   d4                                   ; sign-extend projected Y to word
    add.w   d4,d4                                ; scale projected Y by 2 for word lookup
    move.w  0(a6,d4.w),d2                        ; d2 = byte offset of the destination row within the bitplane

    move.w  d3,d1                                ; copy screen X so we can derive the destination word index
    lsr.w   #4,d1                                ; d1 = screen X / 16 = word column
    add.w   d1,d1                                ; scale word column by 2 because offsets are stored in bytes
    add.w   d1,d2                                ; d2 = final byte offset of the destination word

    not.w   d3                                   ; invert X so low nibble becomes bit position from the left
    and.w   #15,d3                               ; keep only the intra-word bit index 0..15
    moveq   #0,d5                                ; clear d5 before creating the one-bit mask
    bset    d3,d5                                ; d5 = 1 << (15 - (screenX & 15))

    move.w  0(a5,d2.w),d4                        ; d4 = current accumulated mask for this destination word
    bne.s   .m_have_word                         ; skip list insertion if this word was already touched

    movea.l MARG_FRAMEWORDINDEX(sp),a1           ; a1 = unique-word list base
    move.w  d2,0(a1,d0.w)                        ; store the new touched word byte offset
    addq.w  #2,d0                                ; advance unique-word list cursor to the next slot

.m_have_word:                                    ; merge the point bit into the destination word mask
    or.w    d5,d4                                ; add this pixel bit to the accumulated mask
    move.w  d4,0(a5,d2.w)                        ; write the updated mask back to the accumulator

    movea.l d6,a1                                ; restore the advanced Step pointer for the next iteration
    dbra    d7,.m_loop                           ; continue until all points have been processed
    lsr.w   #1,d0                                ; convert byte cursor into word count for the return value
    bra.s   .m_done                              ; leave through the common exit path

.m_done_empty:                                   ; special case for PointCount == 0
    clr.w   d0                                   ; return 0 touched words

.m_done:                                         ; common function exit
    movem.l (sp)+,d2-d7/a2-a6                    ; restore saved registers
    rts                                          ; return with d0.w = unique touched word count

; -----------------------------------------------------------------------------
; UWORD BuildStaticWordMaskFrameAsm(...)
;
; Input:
;   Points         = packed POINT3D8 array
;   PointCount     = number of points to process
;   RotC / RotS    = prebiased rotation lookup bases
;   ProjRows       = prebiased perspective row table base
;   WordMaskAccum  = per-frame sparse word mask buffer
;   FrameWordIndex = list of unique touched word offsets
;
; Output:
;   d0.w = number of unique words touched this frame
;
; Clobbers:
;   d0-d7/a0-a6 (preserved for caller via movem except d0 result)
; -----------------------------------------------------------------------------

_BuildStaticWordMaskFrameAsm::                   ; public symbol with underscore
    movem.l d2-d7/a2-a6,-(sp)                    ; save all non-result registers used by this routine

    movea.l SARG_POINTS(sp),a0                   ; a0 = packed POINT3D8 source pointer
    move.l  SARG_POINTCOUNT(sp),d7               ; d7 = number of points
    beq.w   .s_done_empty                        ; return 0 immediately when no points are present

    subq.w  #1,d7                                ; convert count into DBRA loop counter
    movea.l SARG_ROTC(sp),a2                     ; a2 = RotC lookup base
    movea.l SARG_ROTS(sp),a3                     ; a3 = RotS lookup base
    movea.l SARG_PROJROWS(sp),a4                 ; a4 = ProjRows pointer table base
    movea.l SARG_WORDMASKACCUM(sp),a5            ; a5 = word mask accumulator base
    lea     ScreenRowByteBase+256(pc),a6         ; a6 = row-base table centered around projected Y = 0
    clr.w   d0                                   ; d0 = byte cursor into FrameWordIndex list

.s_loop:                                         ; process one static point
    move.b  (a0)+,d1                             ; d1 = source x as signed byte
    ext.w   d1                                   ; sign-extend x to word
    move.b  (a0)+,d2                             ; d2 = source y as signed byte
    ext.w   d2                                   ; sign-extend y to word
    move.b  (a0)+,d3                             ; d3 = source z as signed byte
    ext.w   d3                                   ; sign-extend z to word

    move.b  0(a2,d1.w),d4                        ; d4 = RotC[x]
    ext.w   d4                                   ; sign-extend rotation lookup to word
    move.b  0(a3,d3.w),d5                        ; d5 = RotS[z]
    ext.w   d5                                   ; sign-extend rotation lookup to word
    add.w   d5,d4                                ; d4 = xr = RotC[x] + RotS[z]

    move.b  0(a2,d3.w),d5                        ; d5 = RotC[z]
    ext.w   d5                                   ; sign-extend rotation lookup to word
    move.b  0(a3,d1.w),d1                        ; d1 = RotS[x]
    ext.w   d1                                   ; sign-extend rotation lookup to word
    sub.w   d1,d5                                ; d5 = zr = RotC[z] - RotS[x]

    add.w   d5,d5                                ; scale zr by 2 for pointer-sized indexing
    add.w   d5,d5                                ; scale zr by 4 because ProjRows contains long pointers
    movea.l 0(a4,d5.w),a1                        ; a1 = ProjRows[zr], already biased for projection X/Y lookup

    move.b  0(a1,d4.w),d3                        ; d3 = projected X offset, already bias-adjusted
    ext.w   d3                                   ; sign-extend projected X to word
    add.w   #CENTER_X,d3                         ; d3 = final screen X in pixels

    move.b  0(a1,d2.w),d4                        ; d4 = projected Y offset, already bias-adjusted
    ext.w   d4                                   ; sign-extend projected Y to word
    add.w   d4,d4                                ; scale projected Y by 2 for word lookup
    move.w  0(a6,d4.w),d2                        ; d2 = byte offset of the destination row within the bitplane

    move.w  d3,d1                                ; copy screen X so we can derive the destination word index
    lsr.w   #4,d1                                ; d1 = screen X / 16 = word column
    add.w   d1,d1                                ; scale word column by 2 because offsets are stored in bytes
    add.w   d1,d2                                ; d2 = final byte offset of the destination word

    not.w   d3                                   ; invert X so low nibble becomes bit position from the left
    and.w   #15,d3                               ; keep only the intra-word bit index 0..15
    moveq   #0,d5                                ; clear d5 before creating the one-bit mask
    bset    d3,d5                                ; d5 = 1 << (15 - (screenX & 15))

    move.w  0(a5,d2.w),d4                        ; d4 = current accumulated mask for this destination word
    bne.s   .s_have_word                         ; skip list insertion if this word was already touched

    movea.l SARG_FRAMEWORDINDEX(sp),a1           ; a1 = unique-word list base
    move.w  d2,0(a1,d0.w)                        ; store the new touched word byte offset
    addq.w  #2,d0                                ; advance unique-word list cursor to the next slot

.s_have_word:                                    ; merge the point bit into the destination word mask
    or.w    d5,d4                                ; add this pixel bit to the accumulated mask
    move.w  d4,0(a5,d2.w)                        ; write the updated mask back to the accumulator
    dbra    d7,.s_loop                           ; continue until all static points have been processed
    lsr.w   #1,d0                                ; convert byte cursor into word count for the return value
    bra.s   .s_done                              ; leave through the common exit path

.s_done_empty:                                   ; special case for PointCount == 0
    clr.w   d0                                   ; return 0 touched words

.s_done:                                         ; common function exit
    movem.l (sp)+,d2-d7/a2-a6                    ; restore saved registers
    rts                                          ; return with d0.w = unique touched word count

; -----------------------------------------------------------------------------
; void UpdateFrameWordsAsm(...)
;
; Input:
;   Plane          = destination bitplane base
;   Prev           = previous frame's touched word offsets
;   PrevCount      = pointer to previous frame word count (updated in place)
;   FrameWordCount = number of words touched in the current frame
;   WordMaskAccum  = current frame sparse word masks
;   FrameWordIndex = current frame touched word offsets
;
; Output:
;   Writes the destination plane and replaces Prev/PrevCount with the current
;   frame's touched word list.
;
; Clobbers:
;   d0/d3-d7/a0-a5 (preserved for caller via movem where needed)
; -----------------------------------------------------------------------------

_UpdateFrameWordsAsm::                           ; public symbol with underscore
    movem.l d3-d7/a2-a5,-(sp)                    ; save all caller-visible registers used by this routine

    movea.l UARG_PLANE(sp),a0                    ; a0 = destination plane base
    movea.l UARG_PREV(sp),a1                     ; a1 = read pointer for previous offsets
    movea.l a1,a2                                ; a2 = write pointer for the next previous-offset list
    movea.l UARG_PREVCOUNT(sp),a3                ; a3 = address of stored previous-count value
    move.l  UARG_FRAMEWORDCOUNT(sp),d7           ; d7 = current frame word count
    movea.l UARG_WORDMASKACCUM(sp),a4            ; a4 = sparse word mask accumulator base
    movea.l UARG_FRAMEWORDINDEX(sp),a5           ; a5 = current frame touched-word list
    clr.w   d6                                   ; d6 = NewCount = 0

    move.w  (a3),d5                              ; d5 = OldCount from the previous frame
    beq.w   .u_old_done                          ; skip old-word processing if no old words exist
    subq.w  #1,d5                                ; convert old count into DBRA loop counter

.u_old_loop:                                     ; walk all words touched in the previous frame
    move.w  (a1)+,d0                             ; d0 = byte offset of one previously touched word

    move.w  0(a4,d0.w),d3                        ; d3 = current frame mask for that word, if any
    move.w  d3,0(a0,d0.w)                        ; overwrite the plane word directly with the current mask
    beq.s   .u_old_skip_store                    ; if current mask is zero, do not keep this word in the new list

    move.w  d0,(a2)+                             ; store surviving offset into the next Prev list
    addq.w  #1,d6                                ; increment the new previous-word count
    clr.w   0(a4,d0.w)                           ; clear the accumulator entry now that it was consumed

.u_old_skip_store:                               ; continue with the next old offset
    dbra    d5,.u_old_loop                       ; loop until every old word has been rewritten

.u_old_done:                                     ; old-word rewrite pass is complete
    tst.l   d7                                   ; check whether the current frame has any touched words at all
    beq.w   .u_done_store                        ; if not, we can store the new count and return
    subq.w  #1,d7                                ; convert current frame count into DBRA loop counter

.u_new_loop:                                     ; walk words touched in the current frame but not seen in old pass
    move.w  (a5)+,d0                             ; d0 = byte offset of one currently touched word
    move.w  0(a4,d0.w),d3                        ; d3 = current frame mask for that word
    beq.s   .u_new_skip                          ; skip if the old pass already consumed and cleared this word

    move.w  d3,0(a0,d0.w)                        ; write the new word directly, plane contents are known zero here
    move.w  d0,(a2)+                             ; append the offset to the next Prev list
    addq.w  #1,d6                                ; increment the new previous-word count
    clr.w   0(a4,d0.w)                           ; clear the accumulator entry now that it was consumed

.u_new_skip:                                     ; continue with the next current-frame offset
    dbra    d7,.u_new_loop                       ; loop until every current-frame word has been visited

.u_done_store:                                   ; finalize the new previous-word metadata
    move.w  d6,(a3)                              ; store NewCount so the next frame can reuse it
    movem.l (sp)+,d3-d7/a2-a5                    ; restore saved registers
    rts                                          ; return to the C caller

    even                                         ; align the following table on an even address
ScreenRowByteBase:                               ; 256-entry table of row byte bases: y -> y * 40
    dc.w        0,   40,   80,  120,  160,  200,  240,  280 ; rows 0..7
    dc.w      320,  360,  400,  440,  480,  520,  560,  600 ; rows 8..15
    dc.w      640,  680,  720,  760,  800,  840,  880,  920 ; rows 16..23
    dc.w      960, 1000, 1040, 1080, 1120, 1160, 1200, 1240 ; rows 24..31
    dc.w     1280, 1320, 1360, 1400, 1440, 1480, 1520, 1560 ; rows 32..39
    dc.w     1600, 1640, 1680, 1720, 1760, 1800, 1840, 1880 ; rows 40..47
    dc.w     1920, 1960, 2000, 2040, 2080, 2120, 2160, 2200 ; rows 48..55
    dc.w     2240, 2280, 2320, 2360, 2400, 2440, 2480, 2520 ; rows 56..63
    dc.w     2560, 2600, 2640, 2680, 2720, 2760, 2800, 2840 ; rows 64..71
    dc.w     2880, 2920, 2960, 3000, 3040, 3080, 3120, 3160 ; rows 72..79
    dc.w     3200, 3240, 3280, 3320, 3360, 3400, 3440, 3480 ; rows 80..87
    dc.w     3520, 3560, 3600, 3640, 3680, 3720, 3760, 3800 ; rows 88..95
    dc.w     3840, 3880, 3920, 3960, 4000, 4040, 4080, 4120 ; rows 96..103
    dc.w     4160, 4200, 4240, 4280, 4320, 4360, 4400, 4440 ; rows 104..111
    dc.w     4480, 4520, 4560, 4600, 4640, 4680, 4720, 4760 ; rows 112..119
    dc.w     4800, 4840, 4880, 4920, 4960, 5000, 5040, 5080 ; rows 120..127
    dc.w     5120, 5160, 5200, 5240, 5280, 5320, 5360, 5400 ; rows 128..135
    dc.w     5440, 5480, 5520, 5560, 5600, 5640, 5680, 5720 ; rows 136..143
    dc.w     5760, 5800, 5840, 5880, 5920, 5960, 6000, 6040 ; rows 144..151
    dc.w     6080, 6120, 6160, 6200, 6240, 6280, 6320, 6360 ; rows 152..159
    dc.w     6400, 6440, 6480, 6520, 6560, 6600, 6640, 6680 ; rows 160..167
    dc.w     6720, 6760, 6800, 6840, 6880, 6920, 6960, 7000 ; rows 168..175
    dc.w     7040, 7080, 7120, 7160, 7200, 7240, 7280, 7320 ; rows 176..183
    dc.w     7360, 7400, 7440, 7480, 7520, 7560, 7600, 7640 ; rows 184..191
    dc.w     7680, 7720, 7760, 7800, 7840, 7880, 7920, 7960 ; rows 192..199
    dc.w     8000, 8040, 8080, 8120, 8160, 8200, 8240, 8280 ; rows 200..207
    dc.w     8320, 8360, 8400, 8440, 8480, 8520, 8560, 8600 ; rows 208..215
    dc.w     8640, 8680, 8720, 8760, 8800, 8840, 8880, 8920 ; rows 216..223
    dc.w     8960, 9000, 9040, 9080, 9120, 9160, 9200, 9240 ; rows 224..231
    dc.w     9280, 9320, 9360, 9400, 9440, 9480, 9520, 9560 ; rows 232..239
    dc.w     9600, 9640, 9680, 9720, 9760, 9800, 9840, 9880 ; rows 240..247
    dc.w     9920, 9960,10000,10040,10080,10120,10160,10200 ; rows 248..255
