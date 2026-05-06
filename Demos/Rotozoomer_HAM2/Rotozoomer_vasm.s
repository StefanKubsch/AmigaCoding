;**********************************************************************
;* 4x4 HAM7 BPLDAT Quirk Rotozoomer ASM Renderer                       *
;*                                                                    *
;* Renders 48x48 HAM cells into four DMA bitplanes.                    *
;* BPL5DAT/BPL6DAT control words are handled by the Copperlist in C.   *
;**********************************************************************

        machine 68000

        xdef    _RenderHamFrameAsm

HAM_ROWS            equ     48
HAM_PAIR_COUNT      equ     24
HAM_FETCH_BYTES     equ     24
HAM_PLANE_BYTES     equ     1152

STACK_ROWU          equ     0
STACK_ROWV          equ     2
STACK_DUDX          equ     4
STACK_DVDX          equ     6
STACK_DUDY          equ     8
STACK_DVDY          equ     10
STACK_LOCAL_BYTES   equ     12

; void RenderHamFrameAsm(a0=Base, a1=TextureCells,
;                        d0=RowU, d1=RowV, d2=DuDx, d3=DvDx,
;                        d4=DuDy, d5=DvDy)

_RenderHamFrameAsm::
        movem.l d2-d7/a2-a6,-(sp)        ; save C registers
        bsr.w   RenderHamFrameCore        ; render frame
        movem.l (sp)+,d2-d7/a2-a6        ; restore C registers
        rts                               ; return to C

RenderHamFrameCore:
        move.l  a6,-(sp)                  ; save caller local pointer
        suba.w  #STACK_LOCAL_BYTES,sp     ; allocate local word parameters

        move.w  d0,STACK_ROWU(sp)         ; store current row U
        move.w  d1,STACK_ROWV(sp)         ; store current row V
        move.w  d2,STACK_DUDX(sp)         ; store horizontal U step
        move.w  #HAM_ROWS,STACK_DVDX(sp)  ; reuse old DvDx slot as row counter
        move.w  d4,STACK_DUDY(sp)         ; store vertical U step
        move.w  d5,STACK_DVDY(sp)         ; store vertical V step
                                            ; d3 keeps horizontal V step in register
.row_loop:
        move.w  STACK_ROWU(sp),d0         ; d0 = current U
        move.w  STACK_ROWV(sp),d1         ; d1 = current V

        movea.l a0,a3                     ; a3 = plane 0 row pointer
        lea     HAM_PLANE_BYTES(a3),a4    ; a4 = plane 1 row pointer
        lea     HAM_PLANE_BYTES(a4),a5    ; a5 = plane 2 row pointer
        lea     HAM_PLANE_BYTES(a5),a6    ; a6 = plane 3 row pointer

        moveq   #(HAM_PAIR_COUNT/4)-1,d5    ; d5 = four two-cell pairs counter
.pair_loop:
        move.w  d1,d6                     ; d6 = V fixed point
        andi.w  #$7F00,d6                 ; d6 = wrapped V row word offset
        move.w  d0,d7                     ; d7 = U fixed point
        lsr.w   #7,d7                     ; d7 = U integer * sizeof(word)
        andi.w  #$00FE,d7                 ; wrap U to 128 columns
        or.w    d7,d6                     ; d6 = texture word offset
        move.w  (a1,d6.w),d6              ; d6 = packed HAM nibbles A

        add.w   STACK_DUDX(sp),d0         ; advance U to sample B
        add.w   d3,d1                     ; advance V to sample B

        move.w  d1,d7                     ; d7 = V fixed point
        andi.w  #$7F00,d7                 ; d7 = wrapped V row word offset
        move.w  d0,d2                     ; d2 = U fixed point
        lsr.w   #7,d2                     ; d2 = U integer * sizeof(word)
        andi.w  #$00FE,d2                 ; wrap U to 128 columns
        or.w    d2,d7                     ; d7 = texture word offset
        move.w  (a1,d7.w),d7              ; d7 = packed HAM nibbles B

        add.w   STACK_DUDX(sp),d0         ; advance U to next pair
        add.w   d3,d1                     ; advance V to next pair

        move.w  d6,d4                     ; d4 = plane 0 nibble A source
        andi.w  #$F000,d4                 ; isolate plane 0 nibble A
        lsr.w   #8,d4                     ; move nibble A to high output nibble
        move.w  d7,d2                     ; d2 = plane 0 nibble B source
        lsr.w   #8,d2                     ; shift high byte down
        lsr.w   #4,d2                     ; move nibble B to low output nibble
        or.w    d2,d4                     ; combine two cells for plane 0
        move.b  d4,(a3)+                  ; write plane 0 byte

        move.w  d6,d4                     ; d4 = plane 1 nibble A source
        andi.w  #$0F00,d4                 ; isolate plane 1 nibble A
        lsr.w   #4,d4                     ; move nibble A to high output nibble
        move.w  d7,d2                     ; d2 = plane 1 nibble B source
        andi.w  #$0F00,d2                 ; isolate plane 1 nibble B
        lsr.w   #8,d2                     ; move nibble B to low output nibble
        or.w    d2,d4                     ; combine two cells for plane 1
        move.b  d4,(a4)+                  ; write plane 1 byte

        move.w  d6,d4                     ; d4 = plane 2 nibble A source
        andi.w  #$00F0,d4                 ; isolate plane 2 nibble A in high nibble
        move.w  d7,d2                     ; d2 = plane 2 nibble B source
        andi.w  #$00F0,d2                 ; isolate plane 2 nibble B
        lsr.w   #4,d2                     ; move nibble B to low output nibble
        or.w    d2,d4                     ; combine two cells for plane 2
        move.b  d4,(a5)+                  ; write plane 2 byte

        move.w  d6,d4                     ; d4 = plane 3 nibble A source
        andi.w  #$000F,d4                 ; isolate plane 3 nibble A
        lsl.w   #4,d4                     ; move nibble A to high output nibble
        move.w  d7,d2                     ; d2 = plane 3 nibble B source
        andi.w  #$000F,d2                 ; isolate plane 3 nibble B
        or.w    d2,d4                     ; combine two cells for plane 3
        move.b  d4,(a6)+                  ; write plane 3 byte

        move.w  d1,d6                     ; d6 = V fixed point
        andi.w  #$7F00,d6                 ; d6 = wrapped V row word offset
        move.w  d0,d7                     ; d7 = U fixed point
        lsr.w   #7,d7                     ; d7 = U integer * sizeof(word)
        andi.w  #$00FE,d7                 ; wrap U to 128 columns
        or.w    d7,d6                     ; d6 = texture word offset
        move.w  (a1,d6.w),d6              ; d6 = packed HAM nibbles A

        add.w   STACK_DUDX(sp),d0         ; advance U to sample B
        add.w   d3,d1                     ; advance V to sample B

        move.w  d1,d7                     ; d7 = V fixed point
        andi.w  #$7F00,d7                 ; d7 = wrapped V row word offset
        move.w  d0,d2                     ; d2 = U fixed point
        lsr.w   #7,d2                     ; d2 = U integer * sizeof(word)
        andi.w  #$00FE,d2                 ; wrap U to 128 columns
        or.w    d2,d7                     ; d7 = texture word offset
        move.w  (a1,d7.w),d7              ; d7 = packed HAM nibbles B

        add.w   STACK_DUDX(sp),d0         ; advance U to next pair
        add.w   d3,d1                     ; advance V to next pair

        move.w  d6,d4                     ; d4 = plane 0 nibble A source
        andi.w  #$F000,d4                 ; isolate plane 0 nibble A
        lsr.w   #8,d4                     ; move nibble A to high output nibble
        move.w  d7,d2                     ; d2 = plane 0 nibble B source
        lsr.w   #8,d2                     ; shift high byte down
        lsr.w   #4,d2                     ; move nibble B to low output nibble
        or.w    d2,d4                     ; combine two cells for plane 0
        move.b  d4,(a3)+                  ; write plane 0 byte

        move.w  d6,d4                     ; d4 = plane 1 nibble A source
        andi.w  #$0F00,d4                 ; isolate plane 1 nibble A
        lsr.w   #4,d4                     ; move nibble A to high output nibble
        move.w  d7,d2                     ; d2 = plane 1 nibble B source
        andi.w  #$0F00,d2                 ; isolate plane 1 nibble B
        lsr.w   #8,d2                     ; move nibble B to low output nibble
        or.w    d2,d4                     ; combine two cells for plane 1
        move.b  d4,(a4)+                  ; write plane 1 byte

        move.w  d6,d4                     ; d4 = plane 2 nibble A source
        andi.w  #$00F0,d4                 ; isolate plane 2 nibble A in high nibble
        move.w  d7,d2                     ; d2 = plane 2 nibble B source
        andi.w  #$00F0,d2                 ; isolate plane 2 nibble B
        lsr.w   #4,d2                     ; move nibble B to low output nibble
        or.w    d2,d4                     ; combine two cells for plane 2
        move.b  d4,(a5)+                  ; write plane 2 byte

        move.w  d6,d4                     ; d4 = plane 3 nibble A source
        andi.w  #$000F,d4                 ; isolate plane 3 nibble A
        lsl.w   #4,d4                     ; move nibble A to high output nibble
        move.w  d7,d2                     ; d2 = plane 3 nibble B source
        andi.w  #$000F,d2                 ; isolate plane 3 nibble B
        or.w    d2,d4                     ; combine two cells for plane 3
        move.b  d4,(a6)+                  ; write plane 3 byte

        move.w  d1,d6                     ; d6 = V fixed point
        andi.w  #$7F00,d6                 ; d6 = wrapped V row word offset
        move.w  d0,d7                     ; d7 = U fixed point
        lsr.w   #7,d7                     ; d7 = U integer * sizeof(word)
        andi.w  #$00FE,d7                 ; wrap U to 128 columns
        or.w    d7,d6                     ; d6 = texture word offset
        move.w  (a1,d6.w),d6              ; d6 = packed HAM nibbles A

        add.w   STACK_DUDX(sp),d0         ; advance U to sample B
        add.w   d3,d1                     ; advance V to sample B

        move.w  d1,d7                     ; d7 = V fixed point
        andi.w  #$7F00,d7                 ; d7 = wrapped V row word offset
        move.w  d0,d2                     ; d2 = U fixed point
        lsr.w   #7,d2                     ; d2 = U integer * sizeof(word)
        andi.w  #$00FE,d2                 ; wrap U to 128 columns
        or.w    d2,d7                     ; d7 = texture word offset
        move.w  (a1,d7.w),d7              ; d7 = packed HAM nibbles B

        add.w   STACK_DUDX(sp),d0         ; advance U to next pair
        add.w   d3,d1                     ; advance V to next pair

        move.w  d6,d4                     ; d4 = plane 0 nibble A source
        andi.w  #$F000,d4                 ; isolate plane 0 nibble A
        lsr.w   #8,d4                     ; move nibble A to high output nibble
        move.w  d7,d2                     ; d2 = plane 0 nibble B source
        lsr.w   #8,d2                     ; shift high byte down
        lsr.w   #4,d2                     ; move nibble B to low output nibble
        or.w    d2,d4                     ; combine two cells for plane 0
        move.b  d4,(a3)+                  ; write plane 0 byte

        move.w  d6,d4                     ; d4 = plane 1 nibble A source
        andi.w  #$0F00,d4                 ; isolate plane 1 nibble A
        lsr.w   #4,d4                     ; move nibble A to high output nibble
        move.w  d7,d2                     ; d2 = plane 1 nibble B source
        andi.w  #$0F00,d2                 ; isolate plane 1 nibble B
        lsr.w   #8,d2                     ; move nibble B to low output nibble
        or.w    d2,d4                     ; combine two cells for plane 1
        move.b  d4,(a4)+                  ; write plane 1 byte

        move.w  d6,d4                     ; d4 = plane 2 nibble A source
        andi.w  #$00F0,d4                 ; isolate plane 2 nibble A in high nibble
        move.w  d7,d2                     ; d2 = plane 2 nibble B source
        andi.w  #$00F0,d2                 ; isolate plane 2 nibble B
        lsr.w   #4,d2                     ; move nibble B to low output nibble
        or.w    d2,d4                     ; combine two cells for plane 2
        move.b  d4,(a5)+                  ; write plane 2 byte

        move.w  d6,d4                     ; d4 = plane 3 nibble A source
        andi.w  #$000F,d4                 ; isolate plane 3 nibble A
        lsl.w   #4,d4                     ; move nibble A to high output nibble
        move.w  d7,d2                     ; d2 = plane 3 nibble B source
        andi.w  #$000F,d2                 ; isolate plane 3 nibble B
        or.w    d2,d4                     ; combine two cells for plane 3
        move.b  d4,(a6)+                  ; write plane 3 byte

        move.w  d1,d6                     ; d6 = V fixed point
        andi.w  #$7F00,d6                 ; d6 = wrapped V row word offset
        move.w  d0,d7                     ; d7 = U fixed point
        lsr.w   #7,d7                     ; d7 = U integer * sizeof(word)
        andi.w  #$00FE,d7                 ; wrap U to 128 columns
        or.w    d7,d6                     ; d6 = texture word offset
        move.w  (a1,d6.w),d6              ; d6 = packed HAM nibbles A

        add.w   STACK_DUDX(sp),d0         ; advance U to sample B
        add.w   d3,d1                     ; advance V to sample B

        move.w  d1,d7                     ; d7 = V fixed point
        andi.w  #$7F00,d7                 ; d7 = wrapped V row word offset
        move.w  d0,d2                     ; d2 = U fixed point
        lsr.w   #7,d2                     ; d2 = U integer * sizeof(word)
        andi.w  #$00FE,d2                 ; wrap U to 128 columns
        or.w    d2,d7                     ; d7 = texture word offset
        move.w  (a1,d7.w),d7              ; d7 = packed HAM nibbles B

        add.w   STACK_DUDX(sp),d0         ; advance U to next pair
        add.w   d3,d1                     ; advance V to next pair

        move.w  d6,d4                     ; d4 = plane 0 nibble A source
        andi.w  #$F000,d4                 ; isolate plane 0 nibble A
        lsr.w   #8,d4                     ; move nibble A to high output nibble
        move.w  d7,d2                     ; d2 = plane 0 nibble B source
        lsr.w   #8,d2                     ; shift high byte down
        lsr.w   #4,d2                     ; move nibble B to low output nibble
        or.w    d2,d4                     ; combine two cells for plane 0
        move.b  d4,(a3)+                  ; write plane 0 byte

        move.w  d6,d4                     ; d4 = plane 1 nibble A source
        andi.w  #$0F00,d4                 ; isolate plane 1 nibble A
        lsr.w   #4,d4                     ; move nibble A to high output nibble
        move.w  d7,d2                     ; d2 = plane 1 nibble B source
        andi.w  #$0F00,d2                 ; isolate plane 1 nibble B
        lsr.w   #8,d2                     ; move nibble B to low output nibble
        or.w    d2,d4                     ; combine two cells for plane 1
        move.b  d4,(a4)+                  ; write plane 1 byte

        move.w  d6,d4                     ; d4 = plane 2 nibble A source
        andi.w  #$00F0,d4                 ; isolate plane 2 nibble A in high nibble
        move.w  d7,d2                     ; d2 = plane 2 nibble B source
        andi.w  #$00F0,d2                 ; isolate plane 2 nibble B
        lsr.w   #4,d2                     ; move nibble B to low output nibble
        or.w    d2,d4                     ; combine two cells for plane 2
        move.b  d4,(a5)+                  ; write plane 2 byte

        move.w  d6,d4                     ; d4 = plane 3 nibble A source
        andi.w  #$000F,d4                 ; isolate plane 3 nibble A
        lsl.w   #4,d4                     ; move nibble A to high output nibble
        move.w  d7,d2                     ; d2 = plane 3 nibble B source
        andi.w  #$000F,d2                 ; isolate plane 3 nibble B
        or.w    d2,d4                     ; combine two cells for plane 3
        move.b  d4,(a6)+                  ; write plane 3 byte

        dbra    d5,.pair_loop             ; render next eight-cell group

        move.w  STACK_DUDY(sp),d2         ; d2 = vertical U step
        add.w   d2,STACK_ROWU(sp)          ; advance row U
        move.w  STACK_DVDY(sp),d2         ; d2 = vertical V step
        add.w   d2,STACK_ROWV(sp)          ; advance row V
        lea     HAM_FETCH_BYTES(a0),a0    ; advance destination base to next row
        subq.w  #1,STACK_DVDX(sp)         ; count rendered row
        bne.w   .row_loop                 ; render next row

        adda.w  #STACK_LOCAL_BYTES,sp     ; free local parameters
        movea.l (sp)+,a6                  ; restore caller local pointer
        rts                               ; return to caller

        xdef    _RunHamMainLoopAsm
ML_BUF0             equ     0
ML_BUF1             equ     4
ML_COP0             equ     8
ML_COP1             equ     12
ML_TEXTURE          equ     16
ML_PARAMS           equ     20
ML_FRAME            equ     24
ML_DRAW             equ     26
ML_LOCAL_BYTES      equ     28

CIAA_PRA_ABS        equ     $00BFE001
COP1LC_ABS          equ     $00DFF080
VPOSR_ABS           equ     $00DFF004

; void RunHamMainLoopAsm(a0=Buffer0, a1=Buffer1, a2=Copper0,
;                        a3=Copper1, a4=TextureCells, d6=FrameParams)

_RunHamMainLoopAsm::
        movem.l d2-d7/a2-a6,-(sp)        ; save C registers
        lea     -ML_LOCAL_BYTES(sp),sp    ; allocate local state
        movea.l sp,a6                     ; a6 = stable local state pointer
        move.l  a0,ML_BUF0(a6)            ; store buffer 0 pointer
        move.l  a1,ML_BUF1(a6)            ; store buffer 1 pointer
        move.l  a2,ML_COP0(a6)            ; store copperlist 0 pointer
        move.l  a3,ML_COP1(a6)            ; store copperlist 1 pointer
        move.l  a4,ML_TEXTURE(a6)         ; store texture cells pointer
        move.l  d6,ML_PARAMS(a6)          ; store frame parameter table pointer
        clr.w   ML_FRAME(a6)              ; start animation frame at 0
        clr.w   ML_DRAW(a6)               ; start drawing into buffer 0

.main_loop:
        btst.b  #6,CIAA_PRA_ABS           ; test left mouse button
        beq.s   .exit_loop                ; exit when button is pressed

        moveq   #0,d0                     ; clear frame index
        move.b  ML_FRAME+1(a6),d0         ; d0 = frame index
        move.w  d0,d1                     ; d1 = frame index
        lsl.w   #3,d0                     ; d0 = frame * 8
        lsl.w   #2,d1                     ; d1 = frame * 4
        add.w   d1,d0                     ; d0 = frame * 12
        movea.l ML_PARAMS(a6),a3          ; a3 = frame parameter table
        lea     (a3,d0.w),a3              ; a3 = current frame parameters

        tst.w   ML_DRAW(a6)               ; test draw buffer
        bne.s   .draw_buffer1             ; branch for buffer 1
        movea.l ML_BUF0(a6),a0            ; a0 = buffer 0
        bra.s   .draw_ready               ; skip buffer 1 path
.draw_buffer1:
        movea.l ML_BUF1(a6),a0            ; a0 = buffer 1
.draw_ready:
        movea.l ML_TEXTURE(a6),a1         ; a1 = texture cells pointer
        move.w  (a3)+,d0                  ; d0 = RowU
        move.w  (a3)+,d1                  ; d1 = RowV
        move.w  (a3)+,d2                  ; d2 = DuDx
        move.w  (a3)+,d3                  ; d3 = DvDx
        move.w  (a3)+,d4                  ; d4 = DuDy
        move.w  (a3)+,d5                  ; d5 = DvDy
        bsr.w   RenderHamFrameCore        ; render frame

        tst.w   ML_DRAW(a6)               ; reload copper pointer after render
        bne.s   .show_buffer1             ; branch for buffer 1
        movea.l ML_COP0(a6),a4            ; a4 = copperlist 0
        bra.s   .show_ready               ; skip buffer 1 path
.show_buffer1:
        movea.l ML_COP1(a6),a4            ; a4 = copperlist 1
.show_ready:
.wait_high_main:
        btst.b  #0,VPOSR_ABS+1            ; wait until vertical high bit is set
        beq.s   .wait_high_main           ; keep waiting above visible area
.wait_low_main:
        cmp.b   #(303&$FF),VPOSR_ABS+2    ; wait for PAL bottom line
        bne.s   .wait_low_main            ; keep waiting for frame boundary
        move.l  a4,COP1LC_ABS             ; show rendered buffer
        eori.w  #1,ML_DRAW(a6)            ; toggle draw buffer
        addq.b  #1,ML_FRAME+1(a6)         ; advance animation frame
        bra.w   .main_loop                ; process next frame

.exit_loop:
.wait_high_exit:
        btst.b  #0,VPOSR_ABS+1            ; wait until vertical high bit is set
        beq.s   .wait_high_exit           ; keep waiting above visible area
.wait_low_exit:
        cmp.b   #(303&$FF),VPOSR_ABS+2    ; wait for PAL bottom line
        bne.s   .wait_low_exit            ; keep waiting for frame boundary
        lea     ML_LOCAL_BYTES(sp),sp     ; free local state
        movem.l (sp)+,d2-d7/a2-a6         ; restore C registers
        rts                               ; return to C
