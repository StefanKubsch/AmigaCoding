;**********************************************************************
;* 4x4 HAM7 BPLDAT Quirk Rotozoomer ASM Renderer                       *
;*                                                                    *
;* Unrolled renderer with persistent pair-table register.           *
;* Renders 48x48 HAM cells into four DMA bitplanes.                    *
;* BPL5DAT/BPL6DAT control words are handled by the Copperlist in C.   *
;**********************************************************************

        machine 68000

HAM_ROWS            equ     48
HAM_PAIR_COUNT      equ     24
HAM_FETCH_BYTES     equ     24
HAM_PLANE_BYTES     equ     1152
STACK_ROWPTR        equ     0
STACK_LOCAL_BYTES   equ     4

; void RenderHamFrameAsm(a0=Base, a1=TextureCellsHighMid, a2=UOffsetTableMid,
;                        a3=PairTables, d4=RowStarts, d5=TextureCellsLowMid,
;                        d0=DuDx, d1=DvDx)

_RenderHamFrameAsm::
        movem.l d2-d7/a2-a6,-(sp)        ; save used C registers
        suba.w  #STACK_LOCAL_BYTES,sp     ; allocate local parameters

        move.l  d4,STACK_ROWPTR(sp)       ; store precomputed row starts
        move.w  d0,d2                     ; d2 = horizontal U step
        move.w  d1,d3                     ; d3 = horizontal V step
        movea.l d5,a4                     ; a4 = low-nibble texture midpoint
        movea.l a3,a6                     ; a6 = persistent pair table base
        move.w  #HAM_ROWS-1,d5            ; d5 = row loop counter
.row_loop:
        movea.l STACK_ROWPTR(sp),a5        ; a5 = current row start pointer
        move.w  (a5)+,d0                  ; d0 = current U
        move.w  (a5)+,d1                  ; d1 = current V
        move.l  a5,STACK_ROWPTR(sp)       ; advance row start pointer
        movea.l a0,a3                     ; a3 = plane 0 row pointer
        lea     HAM_PLANE_BYTES*2(a3),a5  ; a5 = plane 2 row pointer
        lea     HAM_PLANE_BYTES(a5),a0    ; a0 = plane 3 row pointer
        move.w  d1,d6                     ; pair 1: d6 = V fixed point for cell A
        move.b  (a2,d0.w),d6              ; pair 1: add precomputed wrapped U byte
        move.w  (a1,d6.w),d6              ; pair 1: d6 = RGB4 color index A
        add.w   d2,d0                     ; pair 1: advance U to cell B
        add.w   d3,d1                     ; pair 1: advance V to cell B
        move.w  d1,d7                     ; pair 1: d7 = V fixed point for cell B
        move.b  (a2,d0.w),d7              ; pair 1: add precomputed wrapped U byte
        move.w  (a4,d7.w),d7              ; pair 1: d7 = RGB4 color index B
        add.w   d2,d0                     ; pair 1: advance U to next pair
        add.w   d3,d1                     ; pair 1: advance V to next pair
        move.b  (a6,d6.w),d4              ; pair 1: d4 = plane 0 high nibble
        or.b    (a6,d7.w),d4              ; pair 1: add plane 0 low nibble
        move.b  d4,(a3)                   ; pair 1: write plane 0 byte
        move.b  1(a6,d6.w),d4             ; pair 1: d4 = plane 1 high nibble
        or.b    1(a6,d7.w),d4             ; pair 1: add plane 1 low nibble
        move.b  d4,HAM_PLANE_BYTES(a3)    ; pair 1: write plane 1 byte
        addq.l  #1,a3                     ; pair 1: advance plane 0 and plane 1
        move.b  2(a6,d6.w),d4             ; pair 1: d4 = plane 2 high nibble
        or.b    2(a6,d7.w),d4             ; pair 1: add plane 2 low nibble
        move.b  d4,(a5)+                  ; pair 1: write plane 2 byte
        move.b  3(a6,d6.w),d4             ; pair 1: d4 = plane 3 high nibble
        or.b    3(a6,d7.w),d4             ; pair 1: add plane 3 low nibble
        move.b  d4,(a0)+                  ; pair 1: write plane 3 byte

        move.w  d1,d6                     ; pair 2: d6 = V fixed point for cell A
        move.b  (a2,d0.w),d6              ; pair 2: add precomputed wrapped U byte
        move.w  (a1,d6.w),d6              ; pair 2: d6 = RGB4 color index A
        add.w   d2,d0                     ; pair 2: advance U to cell B
        add.w   d3,d1                     ; pair 2: advance V to cell B
        move.w  d1,d7                     ; pair 2: d7 = V fixed point for cell B
        move.b  (a2,d0.w),d7              ; pair 2: add precomputed wrapped U byte
        move.w  (a4,d7.w),d7              ; pair 2: d7 = RGB4 color index B
        add.w   d2,d0                     ; pair 2: advance U to next pair
        add.w   d3,d1                     ; pair 2: advance V to next pair
        move.b  (a6,d6.w),d4              ; pair 2: d4 = plane 0 high nibble
        or.b    (a6,d7.w),d4              ; pair 2: add plane 0 low nibble
        move.b  d4,(a3)                   ; pair 2: write plane 0 byte
        move.b  1(a6,d6.w),d4             ; pair 2: d4 = plane 1 high nibble
        or.b    1(a6,d7.w),d4             ; pair 2: add plane 1 low nibble
        move.b  d4,HAM_PLANE_BYTES(a3)    ; pair 2: write plane 1 byte
        addq.l  #1,a3                     ; pair 2: advance plane 0 and plane 1
        move.b  2(a6,d6.w),d4             ; pair 2: d4 = plane 2 high nibble
        or.b    2(a6,d7.w),d4             ; pair 2: add plane 2 low nibble
        move.b  d4,(a5)+                  ; pair 2: write plane 2 byte
        move.b  3(a6,d6.w),d4             ; pair 2: d4 = plane 3 high nibble
        or.b    3(a6,d7.w),d4             ; pair 2: add plane 3 low nibble
        move.b  d4,(a0)+                  ; pair 2: write plane 3 byte

        move.w  d1,d6                     ; pair 3: d6 = V fixed point for cell A
        move.b  (a2,d0.w),d6              ; pair 3: add precomputed wrapped U byte
        move.w  (a1,d6.w),d6              ; pair 3: d6 = RGB4 color index A
        add.w   d2,d0                     ; pair 3: advance U to cell B
        add.w   d3,d1                     ; pair 3: advance V to cell B
        move.w  d1,d7                     ; pair 3: d7 = V fixed point for cell B
        move.b  (a2,d0.w),d7              ; pair 3: add precomputed wrapped U byte
        move.w  (a4,d7.w),d7              ; pair 3: d7 = RGB4 color index B
        add.w   d2,d0                     ; pair 3: advance U to next pair
        add.w   d3,d1                     ; pair 3: advance V to next pair
        move.b  (a6,d6.w),d4              ; pair 3: d4 = plane 0 high nibble
        or.b    (a6,d7.w),d4              ; pair 3: add plane 0 low nibble
        move.b  d4,(a3)                   ; pair 3: write plane 0 byte
        move.b  1(a6,d6.w),d4             ; pair 3: d4 = plane 1 high nibble
        or.b    1(a6,d7.w),d4             ; pair 3: add plane 1 low nibble
        move.b  d4,HAM_PLANE_BYTES(a3)    ; pair 3: write plane 1 byte
        addq.l  #1,a3                     ; pair 3: advance plane 0 and plane 1
        move.b  2(a6,d6.w),d4             ; pair 3: d4 = plane 2 high nibble
        or.b    2(a6,d7.w),d4             ; pair 3: add plane 2 low nibble
        move.b  d4,(a5)+                  ; pair 3: write plane 2 byte
        move.b  3(a6,d6.w),d4             ; pair 3: d4 = plane 3 high nibble
        or.b    3(a6,d7.w),d4             ; pair 3: add plane 3 low nibble
        move.b  d4,(a0)+                  ; pair 3: write plane 3 byte

        move.w  d1,d6                     ; pair 4: d6 = V fixed point for cell A
        move.b  (a2,d0.w),d6              ; pair 4: add precomputed wrapped U byte
        move.w  (a1,d6.w),d6              ; pair 4: d6 = RGB4 color index A
        add.w   d2,d0                     ; pair 4: advance U to cell B
        add.w   d3,d1                     ; pair 4: advance V to cell B
        move.w  d1,d7                     ; pair 4: d7 = V fixed point for cell B
        move.b  (a2,d0.w),d7              ; pair 4: add precomputed wrapped U byte
        move.w  (a4,d7.w),d7              ; pair 4: d7 = RGB4 color index B
        add.w   d2,d0                     ; pair 4: advance U to next pair
        add.w   d3,d1                     ; pair 4: advance V to next pair
        move.b  (a6,d6.w),d4              ; pair 4: d4 = plane 0 high nibble
        or.b    (a6,d7.w),d4              ; pair 4: add plane 0 low nibble
        move.b  d4,(a3)                   ; pair 4: write plane 0 byte
        move.b  1(a6,d6.w),d4             ; pair 4: d4 = plane 1 high nibble
        or.b    1(a6,d7.w),d4             ; pair 4: add plane 1 low nibble
        move.b  d4,HAM_PLANE_BYTES(a3)    ; pair 4: write plane 1 byte
        addq.l  #1,a3                     ; pair 4: advance plane 0 and plane 1
        move.b  2(a6,d6.w),d4             ; pair 4: d4 = plane 2 high nibble
        or.b    2(a6,d7.w),d4             ; pair 4: add plane 2 low nibble
        move.b  d4,(a5)+                  ; pair 4: write plane 2 byte
        move.b  3(a6,d6.w),d4             ; pair 4: d4 = plane 3 high nibble
        or.b    3(a6,d7.w),d4             ; pair 4: add plane 3 low nibble
        move.b  d4,(a0)+                  ; pair 4: write plane 3 byte

        move.w  d1,d6                     ; pair 5: d6 = V fixed point for cell A
        move.b  (a2,d0.w),d6              ; pair 5: add precomputed wrapped U byte
        move.w  (a1,d6.w),d6              ; pair 5: d6 = RGB4 color index A
        add.w   d2,d0                     ; pair 5: advance U to cell B
        add.w   d3,d1                     ; pair 5: advance V to cell B
        move.w  d1,d7                     ; pair 5: d7 = V fixed point for cell B
        move.b  (a2,d0.w),d7              ; pair 5: add precomputed wrapped U byte
        move.w  (a4,d7.w),d7              ; pair 5: d7 = RGB4 color index B
        add.w   d2,d0                     ; pair 5: advance U to next pair
        add.w   d3,d1                     ; pair 5: advance V to next pair
        move.b  (a6,d6.w),d4              ; pair 5: d4 = plane 0 high nibble
        or.b    (a6,d7.w),d4              ; pair 5: add plane 0 low nibble
        move.b  d4,(a3)                   ; pair 5: write plane 0 byte
        move.b  1(a6,d6.w),d4             ; pair 5: d4 = plane 1 high nibble
        or.b    1(a6,d7.w),d4             ; pair 5: add plane 1 low nibble
        move.b  d4,HAM_PLANE_BYTES(a3)    ; pair 5: write plane 1 byte
        addq.l  #1,a3                     ; pair 5: advance plane 0 and plane 1
        move.b  2(a6,d6.w),d4             ; pair 5: d4 = plane 2 high nibble
        or.b    2(a6,d7.w),d4             ; pair 5: add plane 2 low nibble
        move.b  d4,(a5)+                  ; pair 5: write plane 2 byte
        move.b  3(a6,d6.w),d4             ; pair 5: d4 = plane 3 high nibble
        or.b    3(a6,d7.w),d4             ; pair 5: add plane 3 low nibble
        move.b  d4,(a0)+                  ; pair 5: write plane 3 byte

        move.w  d1,d6                     ; pair 6: d6 = V fixed point for cell A
        move.b  (a2,d0.w),d6              ; pair 6: add precomputed wrapped U byte
        move.w  (a1,d6.w),d6              ; pair 6: d6 = RGB4 color index A
        add.w   d2,d0                     ; pair 6: advance U to cell B
        add.w   d3,d1                     ; pair 6: advance V to cell B
        move.w  d1,d7                     ; pair 6: d7 = V fixed point for cell B
        move.b  (a2,d0.w),d7              ; pair 6: add precomputed wrapped U byte
        move.w  (a4,d7.w),d7              ; pair 6: d7 = RGB4 color index B
        add.w   d2,d0                     ; pair 6: advance U to next pair
        add.w   d3,d1                     ; pair 6: advance V to next pair
        move.b  (a6,d6.w),d4              ; pair 6: d4 = plane 0 high nibble
        or.b    (a6,d7.w),d4              ; pair 6: add plane 0 low nibble
        move.b  d4,(a3)                   ; pair 6: write plane 0 byte
        move.b  1(a6,d6.w),d4             ; pair 6: d4 = plane 1 high nibble
        or.b    1(a6,d7.w),d4             ; pair 6: add plane 1 low nibble
        move.b  d4,HAM_PLANE_BYTES(a3)    ; pair 6: write plane 1 byte
        addq.l  #1,a3                     ; pair 6: advance plane 0 and plane 1
        move.b  2(a6,d6.w),d4             ; pair 6: d4 = plane 2 high nibble
        or.b    2(a6,d7.w),d4             ; pair 6: add plane 2 low nibble
        move.b  d4,(a5)+                  ; pair 6: write plane 2 byte
        move.b  3(a6,d6.w),d4             ; pair 6: d4 = plane 3 high nibble
        or.b    3(a6,d7.w),d4             ; pair 6: add plane 3 low nibble
        move.b  d4,(a0)+                  ; pair 6: write plane 3 byte

        move.w  d1,d6                     ; pair 7: d6 = V fixed point for cell A
        move.b  (a2,d0.w),d6              ; pair 7: add precomputed wrapped U byte
        move.w  (a1,d6.w),d6              ; pair 7: d6 = RGB4 color index A
        add.w   d2,d0                     ; pair 7: advance U to cell B
        add.w   d3,d1                     ; pair 7: advance V to cell B
        move.w  d1,d7                     ; pair 7: d7 = V fixed point for cell B
        move.b  (a2,d0.w),d7              ; pair 7: add precomputed wrapped U byte
        move.w  (a4,d7.w),d7              ; pair 7: d7 = RGB4 color index B
        add.w   d2,d0                     ; pair 7: advance U to next pair
        add.w   d3,d1                     ; pair 7: advance V to next pair
        move.b  (a6,d6.w),d4              ; pair 7: d4 = plane 0 high nibble
        or.b    (a6,d7.w),d4              ; pair 7: add plane 0 low nibble
        move.b  d4,(a3)                   ; pair 7: write plane 0 byte
        move.b  1(a6,d6.w),d4             ; pair 7: d4 = plane 1 high nibble
        or.b    1(a6,d7.w),d4             ; pair 7: add plane 1 low nibble
        move.b  d4,HAM_PLANE_BYTES(a3)    ; pair 7: write plane 1 byte
        addq.l  #1,a3                     ; pair 7: advance plane 0 and plane 1
        move.b  2(a6,d6.w),d4             ; pair 7: d4 = plane 2 high nibble
        or.b    2(a6,d7.w),d4             ; pair 7: add plane 2 low nibble
        move.b  d4,(a5)+                  ; pair 7: write plane 2 byte
        move.b  3(a6,d6.w),d4             ; pair 7: d4 = plane 3 high nibble
        or.b    3(a6,d7.w),d4             ; pair 7: add plane 3 low nibble
        move.b  d4,(a0)+                  ; pair 7: write plane 3 byte

        move.w  d1,d6                     ; pair 8: d6 = V fixed point for cell A
        move.b  (a2,d0.w),d6              ; pair 8: add precomputed wrapped U byte
        move.w  (a1,d6.w),d6              ; pair 8: d6 = RGB4 color index A
        add.w   d2,d0                     ; pair 8: advance U to cell B
        add.w   d3,d1                     ; pair 8: advance V to cell B
        move.w  d1,d7                     ; pair 8: d7 = V fixed point for cell B
        move.b  (a2,d0.w),d7              ; pair 8: add precomputed wrapped U byte
        move.w  (a4,d7.w),d7              ; pair 8: d7 = RGB4 color index B
        add.w   d2,d0                     ; pair 8: advance U to next pair
        add.w   d3,d1                     ; pair 8: advance V to next pair
        move.b  (a6,d6.w),d4              ; pair 8: d4 = plane 0 high nibble
        or.b    (a6,d7.w),d4              ; pair 8: add plane 0 low nibble
        move.b  d4,(a3)                   ; pair 8: write plane 0 byte
        move.b  1(a6,d6.w),d4             ; pair 8: d4 = plane 1 high nibble
        or.b    1(a6,d7.w),d4             ; pair 8: add plane 1 low nibble
        move.b  d4,HAM_PLANE_BYTES(a3)    ; pair 8: write plane 1 byte
        addq.l  #1,a3                     ; pair 8: advance plane 0 and plane 1
        move.b  2(a6,d6.w),d4             ; pair 8: d4 = plane 2 high nibble
        or.b    2(a6,d7.w),d4             ; pair 8: add plane 2 low nibble
        move.b  d4,(a5)+                  ; pair 8: write plane 2 byte
        move.b  3(a6,d6.w),d4             ; pair 8: d4 = plane 3 high nibble
        or.b    3(a6,d7.w),d4             ; pair 8: add plane 3 low nibble
        move.b  d4,(a0)+                  ; pair 8: write plane 3 byte

        move.w  d1,d6                     ; pair 9: d6 = V fixed point for cell A
        move.b  (a2,d0.w),d6              ; pair 9: add precomputed wrapped U byte
        move.w  (a1,d6.w),d6              ; pair 9: d6 = RGB4 color index A
        add.w   d2,d0                     ; pair 9: advance U to cell B
        add.w   d3,d1                     ; pair 9: advance V to cell B
        move.w  d1,d7                     ; pair 9: d7 = V fixed point for cell B
        move.b  (a2,d0.w),d7              ; pair 9: add precomputed wrapped U byte
        move.w  (a4,d7.w),d7              ; pair 9: d7 = RGB4 color index B
        add.w   d2,d0                     ; pair 9: advance U to next pair
        add.w   d3,d1                     ; pair 9: advance V to next pair
        move.b  (a6,d6.w),d4              ; pair 9: d4 = plane 0 high nibble
        or.b    (a6,d7.w),d4              ; pair 9: add plane 0 low nibble
        move.b  d4,(a3)                   ; pair 9: write plane 0 byte
        move.b  1(a6,d6.w),d4             ; pair 9: d4 = plane 1 high nibble
        or.b    1(a6,d7.w),d4             ; pair 9: add plane 1 low nibble
        move.b  d4,HAM_PLANE_BYTES(a3)    ; pair 9: write plane 1 byte
        addq.l  #1,a3                     ; pair 9: advance plane 0 and plane 1
        move.b  2(a6,d6.w),d4             ; pair 9: d4 = plane 2 high nibble
        or.b    2(a6,d7.w),d4             ; pair 9: add plane 2 low nibble
        move.b  d4,(a5)+                  ; pair 9: write plane 2 byte
        move.b  3(a6,d6.w),d4             ; pair 9: d4 = plane 3 high nibble
        or.b    3(a6,d7.w),d4             ; pair 9: add plane 3 low nibble
        move.b  d4,(a0)+                  ; pair 9: write plane 3 byte

        move.w  d1,d6                     ; pair 10: d6 = V fixed point for cell A
        move.b  (a2,d0.w),d6              ; pair 10: add precomputed wrapped U byte
        move.w  (a1,d6.w),d6              ; pair 10: d6 = RGB4 color index A
        add.w   d2,d0                     ; pair 10: advance U to cell B
        add.w   d3,d1                     ; pair 10: advance V to cell B
        move.w  d1,d7                     ; pair 10: d7 = V fixed point for cell B
        move.b  (a2,d0.w),d7              ; pair 10: add precomputed wrapped U byte
        move.w  (a4,d7.w),d7              ; pair 10: d7 = RGB4 color index B
        add.w   d2,d0                     ; pair 10: advance U to next pair
        add.w   d3,d1                     ; pair 10: advance V to next pair
        move.b  (a6,d6.w),d4              ; pair 10: d4 = plane 0 high nibble
        or.b    (a6,d7.w),d4              ; pair 10: add plane 0 low nibble
        move.b  d4,(a3)                   ; pair 10: write plane 0 byte
        move.b  1(a6,d6.w),d4             ; pair 10: d4 = plane 1 high nibble
        or.b    1(a6,d7.w),d4             ; pair 10: add plane 1 low nibble
        move.b  d4,HAM_PLANE_BYTES(a3)    ; pair 10: write plane 1 byte
        addq.l  #1,a3                     ; pair 10: advance plane 0 and plane 1
        move.b  2(a6,d6.w),d4             ; pair 10: d4 = plane 2 high nibble
        or.b    2(a6,d7.w),d4             ; pair 10: add plane 2 low nibble
        move.b  d4,(a5)+                  ; pair 10: write plane 2 byte
        move.b  3(a6,d6.w),d4             ; pair 10: d4 = plane 3 high nibble
        or.b    3(a6,d7.w),d4             ; pair 10: add plane 3 low nibble
        move.b  d4,(a0)+                  ; pair 10: write plane 3 byte

        move.w  d1,d6                     ; pair 11: d6 = V fixed point for cell A
        move.b  (a2,d0.w),d6              ; pair 11: add precomputed wrapped U byte
        move.w  (a1,d6.w),d6              ; pair 11: d6 = RGB4 color index A
        add.w   d2,d0                     ; pair 11: advance U to cell B
        add.w   d3,d1                     ; pair 11: advance V to cell B
        move.w  d1,d7                     ; pair 11: d7 = V fixed point for cell B
        move.b  (a2,d0.w),d7              ; pair 11: add precomputed wrapped U byte
        move.w  (a4,d7.w),d7              ; pair 11: d7 = RGB4 color index B
        add.w   d2,d0                     ; pair 11: advance U to next pair
        add.w   d3,d1                     ; pair 11: advance V to next pair
        move.b  (a6,d6.w),d4              ; pair 11: d4 = plane 0 high nibble
        or.b    (a6,d7.w),d4              ; pair 11: add plane 0 low nibble
        move.b  d4,(a3)                   ; pair 11: write plane 0 byte
        move.b  1(a6,d6.w),d4             ; pair 11: d4 = plane 1 high nibble
        or.b    1(a6,d7.w),d4             ; pair 11: add plane 1 low nibble
        move.b  d4,HAM_PLANE_BYTES(a3)    ; pair 11: write plane 1 byte
        addq.l  #1,a3                     ; pair 11: advance plane 0 and plane 1
        move.b  2(a6,d6.w),d4             ; pair 11: d4 = plane 2 high nibble
        or.b    2(a6,d7.w),d4             ; pair 11: add plane 2 low nibble
        move.b  d4,(a5)+                  ; pair 11: write plane 2 byte
        move.b  3(a6,d6.w),d4             ; pair 11: d4 = plane 3 high nibble
        or.b    3(a6,d7.w),d4             ; pair 11: add plane 3 low nibble
        move.b  d4,(a0)+                  ; pair 11: write plane 3 byte

        move.w  d1,d6                     ; pair 12: d6 = V fixed point for cell A
        move.b  (a2,d0.w),d6              ; pair 12: add precomputed wrapped U byte
        move.w  (a1,d6.w),d6              ; pair 12: d6 = RGB4 color index A
        add.w   d2,d0                     ; pair 12: advance U to cell B
        add.w   d3,d1                     ; pair 12: advance V to cell B
        move.w  d1,d7                     ; pair 12: d7 = V fixed point for cell B
        move.b  (a2,d0.w),d7              ; pair 12: add precomputed wrapped U byte
        move.w  (a4,d7.w),d7              ; pair 12: d7 = RGB4 color index B
        add.w   d2,d0                     ; pair 12: advance U to next pair
        add.w   d3,d1                     ; pair 12: advance V to next pair
        move.b  (a6,d6.w),d4              ; pair 12: d4 = plane 0 high nibble
        or.b    (a6,d7.w),d4              ; pair 12: add plane 0 low nibble
        move.b  d4,(a3)                   ; pair 12: write plane 0 byte
        move.b  1(a6,d6.w),d4             ; pair 12: d4 = plane 1 high nibble
        or.b    1(a6,d7.w),d4             ; pair 12: add plane 1 low nibble
        move.b  d4,HAM_PLANE_BYTES(a3)    ; pair 12: write plane 1 byte
        addq.l  #1,a3                     ; pair 12: advance plane 0 and plane 1
        move.b  2(a6,d6.w),d4             ; pair 12: d4 = plane 2 high nibble
        or.b    2(a6,d7.w),d4             ; pair 12: add plane 2 low nibble
        move.b  d4,(a5)+                  ; pair 12: write plane 2 byte
        move.b  3(a6,d6.w),d4             ; pair 12: d4 = plane 3 high nibble
        or.b    3(a6,d7.w),d4             ; pair 12: add plane 3 low nibble
        move.b  d4,(a0)+                  ; pair 12: write plane 3 byte

        move.w  d1,d6                     ; pair 13: d6 = V fixed point for cell A
        move.b  (a2,d0.w),d6              ; pair 13: add precomputed wrapped U byte
        move.w  (a1,d6.w),d6              ; pair 13: d6 = RGB4 color index A
        add.w   d2,d0                     ; pair 13: advance U to cell B
        add.w   d3,d1                     ; pair 13: advance V to cell B
        move.w  d1,d7                     ; pair 13: d7 = V fixed point for cell B
        move.b  (a2,d0.w),d7              ; pair 13: add precomputed wrapped U byte
        move.w  (a4,d7.w),d7              ; pair 13: d7 = RGB4 color index B
        add.w   d2,d0                     ; pair 13: advance U to next pair
        add.w   d3,d1                     ; pair 13: advance V to next pair
        move.b  (a6,d6.w),d4              ; pair 13: d4 = plane 0 high nibble
        or.b    (a6,d7.w),d4              ; pair 13: add plane 0 low nibble
        move.b  d4,(a3)                   ; pair 13: write plane 0 byte
        move.b  1(a6,d6.w),d4             ; pair 13: d4 = plane 1 high nibble
        or.b    1(a6,d7.w),d4             ; pair 13: add plane 1 low nibble
        move.b  d4,HAM_PLANE_BYTES(a3)    ; pair 13: write plane 1 byte
        addq.l  #1,a3                     ; pair 13: advance plane 0 and plane 1
        move.b  2(a6,d6.w),d4             ; pair 13: d4 = plane 2 high nibble
        or.b    2(a6,d7.w),d4             ; pair 13: add plane 2 low nibble
        move.b  d4,(a5)+                  ; pair 13: write plane 2 byte
        move.b  3(a6,d6.w),d4             ; pair 13: d4 = plane 3 high nibble
        or.b    3(a6,d7.w),d4             ; pair 13: add plane 3 low nibble
        move.b  d4,(a0)+                  ; pair 13: write plane 3 byte

        move.w  d1,d6                     ; pair 14: d6 = V fixed point for cell A
        move.b  (a2,d0.w),d6              ; pair 14: add precomputed wrapped U byte
        move.w  (a1,d6.w),d6              ; pair 14: d6 = RGB4 color index A
        add.w   d2,d0                     ; pair 14: advance U to cell B
        add.w   d3,d1                     ; pair 14: advance V to cell B
        move.w  d1,d7                     ; pair 14: d7 = V fixed point for cell B
        move.b  (a2,d0.w),d7              ; pair 14: add precomputed wrapped U byte
        move.w  (a4,d7.w),d7              ; pair 14: d7 = RGB4 color index B
        add.w   d2,d0                     ; pair 14: advance U to next pair
        add.w   d3,d1                     ; pair 14: advance V to next pair
        move.b  (a6,d6.w),d4              ; pair 14: d4 = plane 0 high nibble
        or.b    (a6,d7.w),d4              ; pair 14: add plane 0 low nibble
        move.b  d4,(a3)                   ; pair 14: write plane 0 byte
        move.b  1(a6,d6.w),d4             ; pair 14: d4 = plane 1 high nibble
        or.b    1(a6,d7.w),d4             ; pair 14: add plane 1 low nibble
        move.b  d4,HAM_PLANE_BYTES(a3)    ; pair 14: write plane 1 byte
        addq.l  #1,a3                     ; pair 14: advance plane 0 and plane 1
        move.b  2(a6,d6.w),d4             ; pair 14: d4 = plane 2 high nibble
        or.b    2(a6,d7.w),d4             ; pair 14: add plane 2 low nibble
        move.b  d4,(a5)+                  ; pair 14: write plane 2 byte
        move.b  3(a6,d6.w),d4             ; pair 14: d4 = plane 3 high nibble
        or.b    3(a6,d7.w),d4             ; pair 14: add plane 3 low nibble
        move.b  d4,(a0)+                  ; pair 14: write plane 3 byte

        move.w  d1,d6                     ; pair 15: d6 = V fixed point for cell A
        move.b  (a2,d0.w),d6              ; pair 15: add precomputed wrapped U byte
        move.w  (a1,d6.w),d6              ; pair 15: d6 = RGB4 color index A
        add.w   d2,d0                     ; pair 15: advance U to cell B
        add.w   d3,d1                     ; pair 15: advance V to cell B
        move.w  d1,d7                     ; pair 15: d7 = V fixed point for cell B
        move.b  (a2,d0.w),d7              ; pair 15: add precomputed wrapped U byte
        move.w  (a4,d7.w),d7              ; pair 15: d7 = RGB4 color index B
        add.w   d2,d0                     ; pair 15: advance U to next pair
        add.w   d3,d1                     ; pair 15: advance V to next pair
        move.b  (a6,d6.w),d4              ; pair 15: d4 = plane 0 high nibble
        or.b    (a6,d7.w),d4              ; pair 15: add plane 0 low nibble
        move.b  d4,(a3)                   ; pair 15: write plane 0 byte
        move.b  1(a6,d6.w),d4             ; pair 15: d4 = plane 1 high nibble
        or.b    1(a6,d7.w),d4             ; pair 15: add plane 1 low nibble
        move.b  d4,HAM_PLANE_BYTES(a3)    ; pair 15: write plane 1 byte
        addq.l  #1,a3                     ; pair 15: advance plane 0 and plane 1
        move.b  2(a6,d6.w),d4             ; pair 15: d4 = plane 2 high nibble
        or.b    2(a6,d7.w),d4             ; pair 15: add plane 2 low nibble
        move.b  d4,(a5)+                  ; pair 15: write plane 2 byte
        move.b  3(a6,d6.w),d4             ; pair 15: d4 = plane 3 high nibble
        or.b    3(a6,d7.w),d4             ; pair 15: add plane 3 low nibble
        move.b  d4,(a0)+                  ; pair 15: write plane 3 byte

        move.w  d1,d6                     ; pair 16: d6 = V fixed point for cell A
        move.b  (a2,d0.w),d6              ; pair 16: add precomputed wrapped U byte
        move.w  (a1,d6.w),d6              ; pair 16: d6 = RGB4 color index A
        add.w   d2,d0                     ; pair 16: advance U to cell B
        add.w   d3,d1                     ; pair 16: advance V to cell B
        move.w  d1,d7                     ; pair 16: d7 = V fixed point for cell B
        move.b  (a2,d0.w),d7              ; pair 16: add precomputed wrapped U byte
        move.w  (a4,d7.w),d7              ; pair 16: d7 = RGB4 color index B
        add.w   d2,d0                     ; pair 16: advance U to next pair
        add.w   d3,d1                     ; pair 16: advance V to next pair
        move.b  (a6,d6.w),d4              ; pair 16: d4 = plane 0 high nibble
        or.b    (a6,d7.w),d4              ; pair 16: add plane 0 low nibble
        move.b  d4,(a3)                   ; pair 16: write plane 0 byte
        move.b  1(a6,d6.w),d4             ; pair 16: d4 = plane 1 high nibble
        or.b    1(a6,d7.w),d4             ; pair 16: add plane 1 low nibble
        move.b  d4,HAM_PLANE_BYTES(a3)    ; pair 16: write plane 1 byte
        addq.l  #1,a3                     ; pair 16: advance plane 0 and plane 1
        move.b  2(a6,d6.w),d4             ; pair 16: d4 = plane 2 high nibble
        or.b    2(a6,d7.w),d4             ; pair 16: add plane 2 low nibble
        move.b  d4,(a5)+                  ; pair 16: write plane 2 byte
        move.b  3(a6,d6.w),d4             ; pair 16: d4 = plane 3 high nibble
        or.b    3(a6,d7.w),d4             ; pair 16: add plane 3 low nibble
        move.b  d4,(a0)+                  ; pair 16: write plane 3 byte

        move.w  d1,d6                     ; pair 17: d6 = V fixed point for cell A
        move.b  (a2,d0.w),d6              ; pair 17: add precomputed wrapped U byte
        move.w  (a1,d6.w),d6              ; pair 17: d6 = RGB4 color index A
        add.w   d2,d0                     ; pair 17: advance U to cell B
        add.w   d3,d1                     ; pair 17: advance V to cell B
        move.w  d1,d7                     ; pair 17: d7 = V fixed point for cell B
        move.b  (a2,d0.w),d7              ; pair 17: add precomputed wrapped U byte
        move.w  (a4,d7.w),d7              ; pair 17: d7 = RGB4 color index B
        add.w   d2,d0                     ; pair 17: advance U to next pair
        add.w   d3,d1                     ; pair 17: advance V to next pair
        move.b  (a6,d6.w),d4              ; pair 17: d4 = plane 0 high nibble
        or.b    (a6,d7.w),d4              ; pair 17: add plane 0 low nibble
        move.b  d4,(a3)                   ; pair 17: write plane 0 byte
        move.b  1(a6,d6.w),d4             ; pair 17: d4 = plane 1 high nibble
        or.b    1(a6,d7.w),d4             ; pair 17: add plane 1 low nibble
        move.b  d4,HAM_PLANE_BYTES(a3)    ; pair 17: write plane 1 byte
        addq.l  #1,a3                     ; pair 17: advance plane 0 and plane 1
        move.b  2(a6,d6.w),d4             ; pair 17: d4 = plane 2 high nibble
        or.b    2(a6,d7.w),d4             ; pair 17: add plane 2 low nibble
        move.b  d4,(a5)+                  ; pair 17: write plane 2 byte
        move.b  3(a6,d6.w),d4             ; pair 17: d4 = plane 3 high nibble
        or.b    3(a6,d7.w),d4             ; pair 17: add plane 3 low nibble
        move.b  d4,(a0)+                  ; pair 17: write plane 3 byte

        move.w  d1,d6                     ; pair 18: d6 = V fixed point for cell A
        move.b  (a2,d0.w),d6              ; pair 18: add precomputed wrapped U byte
        move.w  (a1,d6.w),d6              ; pair 18: d6 = RGB4 color index A
        add.w   d2,d0                     ; pair 18: advance U to cell B
        add.w   d3,d1                     ; pair 18: advance V to cell B
        move.w  d1,d7                     ; pair 18: d7 = V fixed point for cell B
        move.b  (a2,d0.w),d7              ; pair 18: add precomputed wrapped U byte
        move.w  (a4,d7.w),d7              ; pair 18: d7 = RGB4 color index B
        add.w   d2,d0                     ; pair 18: advance U to next pair
        add.w   d3,d1                     ; pair 18: advance V to next pair
        move.b  (a6,d6.w),d4              ; pair 18: d4 = plane 0 high nibble
        or.b    (a6,d7.w),d4              ; pair 18: add plane 0 low nibble
        move.b  d4,(a3)                   ; pair 18: write plane 0 byte
        move.b  1(a6,d6.w),d4             ; pair 18: d4 = plane 1 high nibble
        or.b    1(a6,d7.w),d4             ; pair 18: add plane 1 low nibble
        move.b  d4,HAM_PLANE_BYTES(a3)    ; pair 18: write plane 1 byte
        addq.l  #1,a3                     ; pair 18: advance plane 0 and plane 1
        move.b  2(a6,d6.w),d4             ; pair 18: d4 = plane 2 high nibble
        or.b    2(a6,d7.w),d4             ; pair 18: add plane 2 low nibble
        move.b  d4,(a5)+                  ; pair 18: write plane 2 byte
        move.b  3(a6,d6.w),d4             ; pair 18: d4 = plane 3 high nibble
        or.b    3(a6,d7.w),d4             ; pair 18: add plane 3 low nibble
        move.b  d4,(a0)+                  ; pair 18: write plane 3 byte

        move.w  d1,d6                     ; pair 19: d6 = V fixed point for cell A
        move.b  (a2,d0.w),d6              ; pair 19: add precomputed wrapped U byte
        move.w  (a1,d6.w),d6              ; pair 19: d6 = RGB4 color index A
        add.w   d2,d0                     ; pair 19: advance U to cell B
        add.w   d3,d1                     ; pair 19: advance V to cell B
        move.w  d1,d7                     ; pair 19: d7 = V fixed point for cell B
        move.b  (a2,d0.w),d7              ; pair 19: add precomputed wrapped U byte
        move.w  (a4,d7.w),d7              ; pair 19: d7 = RGB4 color index B
        add.w   d2,d0                     ; pair 19: advance U to next pair
        add.w   d3,d1                     ; pair 19: advance V to next pair
        move.b  (a6,d6.w),d4              ; pair 19: d4 = plane 0 high nibble
        or.b    (a6,d7.w),d4              ; pair 19: add plane 0 low nibble
        move.b  d4,(a3)                   ; pair 19: write plane 0 byte
        move.b  1(a6,d6.w),d4             ; pair 19: d4 = plane 1 high nibble
        or.b    1(a6,d7.w),d4             ; pair 19: add plane 1 low nibble
        move.b  d4,HAM_PLANE_BYTES(a3)    ; pair 19: write plane 1 byte
        addq.l  #1,a3                     ; pair 19: advance plane 0 and plane 1
        move.b  2(a6,d6.w),d4             ; pair 19: d4 = plane 2 high nibble
        or.b    2(a6,d7.w),d4             ; pair 19: add plane 2 low nibble
        move.b  d4,(a5)+                  ; pair 19: write plane 2 byte
        move.b  3(a6,d6.w),d4             ; pair 19: d4 = plane 3 high nibble
        or.b    3(a6,d7.w),d4             ; pair 19: add plane 3 low nibble
        move.b  d4,(a0)+                  ; pair 19: write plane 3 byte

        move.w  d1,d6                     ; pair 20: d6 = V fixed point for cell A
        move.b  (a2,d0.w),d6              ; pair 20: add precomputed wrapped U byte
        move.w  (a1,d6.w),d6              ; pair 20: d6 = RGB4 color index A
        add.w   d2,d0                     ; pair 20: advance U to cell B
        add.w   d3,d1                     ; pair 20: advance V to cell B
        move.w  d1,d7                     ; pair 20: d7 = V fixed point for cell B
        move.b  (a2,d0.w),d7              ; pair 20: add precomputed wrapped U byte
        move.w  (a4,d7.w),d7              ; pair 20: d7 = RGB4 color index B
        add.w   d2,d0                     ; pair 20: advance U to next pair
        add.w   d3,d1                     ; pair 20: advance V to next pair
        move.b  (a6,d6.w),d4              ; pair 20: d4 = plane 0 high nibble
        or.b    (a6,d7.w),d4              ; pair 20: add plane 0 low nibble
        move.b  d4,(a3)                   ; pair 20: write plane 0 byte
        move.b  1(a6,d6.w),d4             ; pair 20: d4 = plane 1 high nibble
        or.b    1(a6,d7.w),d4             ; pair 20: add plane 1 low nibble
        move.b  d4,HAM_PLANE_BYTES(a3)    ; pair 20: write plane 1 byte
        addq.l  #1,a3                     ; pair 20: advance plane 0 and plane 1
        move.b  2(a6,d6.w),d4             ; pair 20: d4 = plane 2 high nibble
        or.b    2(a6,d7.w),d4             ; pair 20: add plane 2 low nibble
        move.b  d4,(a5)+                  ; pair 20: write plane 2 byte
        move.b  3(a6,d6.w),d4             ; pair 20: d4 = plane 3 high nibble
        or.b    3(a6,d7.w),d4             ; pair 20: add plane 3 low nibble
        move.b  d4,(a0)+                  ; pair 20: write plane 3 byte

        move.w  d1,d6                     ; pair 21: d6 = V fixed point for cell A
        move.b  (a2,d0.w),d6              ; pair 21: add precomputed wrapped U byte
        move.w  (a1,d6.w),d6              ; pair 21: d6 = RGB4 color index A
        add.w   d2,d0                     ; pair 21: advance U to cell B
        add.w   d3,d1                     ; pair 21: advance V to cell B
        move.w  d1,d7                     ; pair 21: d7 = V fixed point for cell B
        move.b  (a2,d0.w),d7              ; pair 21: add precomputed wrapped U byte
        move.w  (a4,d7.w),d7              ; pair 21: d7 = RGB4 color index B
        add.w   d2,d0                     ; pair 21: advance U to next pair
        add.w   d3,d1                     ; pair 21: advance V to next pair
        move.b  (a6,d6.w),d4              ; pair 21: d4 = plane 0 high nibble
        or.b    (a6,d7.w),d4              ; pair 21: add plane 0 low nibble
        move.b  d4,(a3)                   ; pair 21: write plane 0 byte
        move.b  1(a6,d6.w),d4             ; pair 21: d4 = plane 1 high nibble
        or.b    1(a6,d7.w),d4             ; pair 21: add plane 1 low nibble
        move.b  d4,HAM_PLANE_BYTES(a3)    ; pair 21: write plane 1 byte
        addq.l  #1,a3                     ; pair 21: advance plane 0 and plane 1
        move.b  2(a6,d6.w),d4             ; pair 21: d4 = plane 2 high nibble
        or.b    2(a6,d7.w),d4             ; pair 21: add plane 2 low nibble
        move.b  d4,(a5)+                  ; pair 21: write plane 2 byte
        move.b  3(a6,d6.w),d4             ; pair 21: d4 = plane 3 high nibble
        or.b    3(a6,d7.w),d4             ; pair 21: add plane 3 low nibble
        move.b  d4,(a0)+                  ; pair 21: write plane 3 byte

        move.w  d1,d6                     ; pair 22: d6 = V fixed point for cell A
        move.b  (a2,d0.w),d6              ; pair 22: add precomputed wrapped U byte
        move.w  (a1,d6.w),d6              ; pair 22: d6 = RGB4 color index A
        add.w   d2,d0                     ; pair 22: advance U to cell B
        add.w   d3,d1                     ; pair 22: advance V to cell B
        move.w  d1,d7                     ; pair 22: d7 = V fixed point for cell B
        move.b  (a2,d0.w),d7              ; pair 22: add precomputed wrapped U byte
        move.w  (a4,d7.w),d7              ; pair 22: d7 = RGB4 color index B
        add.w   d2,d0                     ; pair 22: advance U to next pair
        add.w   d3,d1                     ; pair 22: advance V to next pair
        move.b  (a6,d6.w),d4              ; pair 22: d4 = plane 0 high nibble
        or.b    (a6,d7.w),d4              ; pair 22: add plane 0 low nibble
        move.b  d4,(a3)                   ; pair 22: write plane 0 byte
        move.b  1(a6,d6.w),d4             ; pair 22: d4 = plane 1 high nibble
        or.b    1(a6,d7.w),d4             ; pair 22: add plane 1 low nibble
        move.b  d4,HAM_PLANE_BYTES(a3)    ; pair 22: write plane 1 byte
        addq.l  #1,a3                     ; pair 22: advance plane 0 and plane 1
        move.b  2(a6,d6.w),d4             ; pair 22: d4 = plane 2 high nibble
        or.b    2(a6,d7.w),d4             ; pair 22: add plane 2 low nibble
        move.b  d4,(a5)+                  ; pair 22: write plane 2 byte
        move.b  3(a6,d6.w),d4             ; pair 22: d4 = plane 3 high nibble
        or.b    3(a6,d7.w),d4             ; pair 22: add plane 3 low nibble
        move.b  d4,(a0)+                  ; pair 22: write plane 3 byte

        move.w  d1,d6                     ; pair 23: d6 = V fixed point for cell A
        move.b  (a2,d0.w),d6              ; pair 23: add precomputed wrapped U byte
        move.w  (a1,d6.w),d6              ; pair 23: d6 = RGB4 color index A
        add.w   d2,d0                     ; pair 23: advance U to cell B
        add.w   d3,d1                     ; pair 23: advance V to cell B
        move.w  d1,d7                     ; pair 23: d7 = V fixed point for cell B
        move.b  (a2,d0.w),d7              ; pair 23: add precomputed wrapped U byte
        move.w  (a4,d7.w),d7              ; pair 23: d7 = RGB4 color index B
        add.w   d2,d0                     ; pair 23: advance U to next pair
        add.w   d3,d1                     ; pair 23: advance V to next pair
        move.b  (a6,d6.w),d4              ; pair 23: d4 = plane 0 high nibble
        or.b    (a6,d7.w),d4              ; pair 23: add plane 0 low nibble
        move.b  d4,(a3)                   ; pair 23: write plane 0 byte
        move.b  1(a6,d6.w),d4             ; pair 23: d4 = plane 1 high nibble
        or.b    1(a6,d7.w),d4             ; pair 23: add plane 1 low nibble
        move.b  d4,HAM_PLANE_BYTES(a3)    ; pair 23: write plane 1 byte
        addq.l  #1,a3                     ; pair 23: advance plane 0 and plane 1
        move.b  2(a6,d6.w),d4             ; pair 23: d4 = plane 2 high nibble
        or.b    2(a6,d7.w),d4             ; pair 23: add plane 2 low nibble
        move.b  d4,(a5)+                  ; pair 23: write plane 2 byte
        move.b  3(a6,d6.w),d4             ; pair 23: d4 = plane 3 high nibble
        or.b    3(a6,d7.w),d4             ; pair 23: add plane 3 low nibble
        move.b  d4,(a0)+                  ; pair 23: write plane 3 byte

        move.w  d1,d6                     ; pair 24: d6 = V fixed point for cell A
        move.b  (a2,d0.w),d6              ; pair 24: add precomputed wrapped U byte
        move.w  (a1,d6.w),d6              ; pair 24: d6 = RGB4 color index A
        add.w   d2,d0                     ; pair 24: advance U to cell B
        add.w   d3,d1                     ; pair 24: advance V to cell B
        move.w  d1,d7                     ; pair 24: d7 = V fixed point for cell B
        move.b  (a2,d0.w),d7              ; pair 24: add precomputed wrapped U byte
        move.w  (a4,d7.w),d7              ; pair 24: d7 = RGB4 color index B
        add.w   d2,d0                     ; pair 24: advance U to next pair
        add.w   d3,d1                     ; pair 24: advance V to next pair
        move.b  (a6,d6.w),d4              ; pair 24: d4 = plane 0 high nibble
        or.b    (a6,d7.w),d4              ; pair 24: add plane 0 low nibble
        move.b  d4,(a3)                   ; pair 24: write plane 0 byte
        move.b  1(a6,d6.w),d4             ; pair 24: d4 = plane 1 high nibble
        or.b    1(a6,d7.w),d4             ; pair 24: add plane 1 low nibble
        move.b  d4,HAM_PLANE_BYTES(a3)    ; pair 24: write plane 1 byte
        addq.l  #1,a3                     ; pair 24: advance plane 0 and plane 1
        move.b  2(a6,d6.w),d4             ; pair 24: d4 = plane 2 high nibble
        or.b    2(a6,d7.w),d4             ; pair 24: add plane 2 low nibble
        move.b  d4,(a5)+                  ; pair 24: write plane 2 byte
        move.b  3(a6,d6.w),d4             ; pair 24: d4 = plane 3 high nibble
        or.b    3(a6,d7.w),d4             ; pair 24: add plane 3 low nibble
        move.b  d4,(a0)+                  ; pair 24: write plane 3 byte

        movea.l a3,a0                     ; use advanced plane 0 pointer as next row base
        dbra    d5,.row_loop              ; render next row

        adda.w  #STACK_LOCAL_BYTES,sp     ; free local parameters
        movem.l (sp)+,d2-d7/a2-a6        ; restore used C registers
        rts                               ; return to C
