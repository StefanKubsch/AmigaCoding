;**********************************************************************
;* 4x4 HAM7 Rotozoomer                                                *
;*                                                                    *
;**********************************************************************

    machine 68000                          ; Assemble for plain 68000.

CUSTOM_BASE             equ $dff000        ; Base address of the Amiga custom chips.
DMACONR_OFF             equ $0002          ; DMACONR offset used to poll the blitter busy bit.
BLTCON0_OFF             equ $0040          ; BLTCON0/BLTCON1 write pair offset.
BLTBPTH_OFF             equ $004c          ; Source B pointer high/low offset.
BLTAPTH_OFF             equ $0050          ; Source A pointer high/low offset.
BLTDPTH_OFF             equ $0054          ; Destination pointer high/low offset.
BLTSIZE_OFF             equ $0058          ; BLTSIZE offset.

ROTO_COLUMNS            equ 28             ; Logical columns per frame.
ROTO_FETCH_BYTES        equ 14             ; Bytes per compact display row.
ROTO_ROWS               equ 48             ; Logical rows per frame.
ROTO_CHUNK_ROWS         equ 4              ; Rows rendered per slice.
ROTOFRAME_DUDX          equ 0              ; Slice field offset: DuDx.
ROTOFRAME_DVDX          equ 2              ; Slice field offset: DvDx.
ROTOFRAME_STARTU        equ 4              ; Slice field offset: StartU of the first row in this slice.
ROTOFRAME_STARTV        equ 6              ; Slice field offset: StartV of the first row in this slice.
ROTO_PLANE_BYTES        equ (ROTO_FETCH_BYTES*ROTO_ROWS) ; Size of one compact DMA plane.
ROTO_SCREEN_BYTES       equ (ROTO_PLANE_BYTES*4)         ; Size of all four compact DMA planes.
ROTO_C2P_BLTSIZE        equ ((ROTO_PLANE_BYTES*32)+1)    ; Full-plane 1-word-wide blit.

BLIT_EXTRACT_4_RIGHT    equ (($4de4<<16)|0) ; Ascending/right-going extractor setup.
BLIT_EXTRACT_4_LEFT     equ (($4dd8<<16)|2) ; Descending/left-going extractor setup.

BUILD_OFFSET_ONE_D4 macro                  ; Convert one U/V pair into one centered direct-table byte offset in d4.
    move.w  d1,d6                          ; Copy the current V coordinate.
    andi.w  #$7f00,d6                      ; Keep the texture row bits for a 128x128 texture.
    add.w   d6,d6                          ; Convert the row contribution from 2-byte texels to 4-byte descriptors.
    move.w  d0,d7                          ; Copy the current U coordinate.
    lsr.w   #6,d7                          ; Convert U to a 4-byte descriptor offset inside the row.
    andi.w  #$01fc,d7                      ; Mask the column to a valid 4-byte descriptor offset.
    add.w   d7,d6                          ; Combine row and column into the direct-table byte offset.
    eori.w  #$8000,d6                      ; Re-center the offset for signed 16-bit indexed addressing.
    move.w  d6,d4                          ; Return the centered descriptor offset in d4.
    add.w   d2,d0                          ; Advance U by DuDx for the next texel.
    add.w   d3,d1                          ; Advance V by DvDx for the next texel.
    endm                                   ; End of d4 offset builder.

BUILD_OFFSET_ONE_D5 macro                  ; Convert one U/V pair into one centered direct-table byte offset in d5.
    move.w  d1,d6                          ; Copy the current V coordinate.
    andi.w  #$7f00,d6                      ; Keep the texture row bits for a 128x128 texture.
    add.w   d6,d6                          ; Convert the row contribution from 2-byte texels to 4-byte descriptors.
    move.w  d0,d7                          ; Copy the current U coordinate.
    lsr.w   #6,d7                          ; Convert U to a 4-byte descriptor offset inside the row.
    andi.w  #$01fc,d7                      ; Mask the column to a valid 4-byte descriptor offset.
    add.w   d7,d6                          ; Combine row and column into the direct-table byte offset.
    eori.w  #$8000,d6                      ; Re-center the offset for signed 16-bit indexed addressing.
    move.w  d6,d5                          ; Return the centered descriptor offset in d5.
    add.w   d2,d0                          ; Advance U by DuDx for the next texel.
    add.w   d3,d1                          ; Advance V by DvDx for the next texel.
    endm                                   ; End of d5 offset builder.

BUILD_OFFSET_GROUP macro                   ; Build four centered direct-table offsets and store them as two packed longwords.
    BUILD_OFFSET_ONE_D4                    ; Build offset 0 into d4 low word.
    swap    d4                             ; Move offset 0 into d4 high word.
    BUILD_OFFSET_ONE_D4                    ; Build offset 1 into d4 low word.
    BUILD_OFFSET_ONE_D5                    ; Build offset 2 into d5 low word.
    swap    d5                             ; Move offset 2 into d5 high word.
    BUILD_OFFSET_ONE_D5                    ; Build offset 3 into d5 low word.
    move.l  d4,(a1)+                       ; Store offsets 0/1 with one longword write.
    move.l  d5,(a1)+                       ; Store offsets 2/3 with one longword write.
    endm                                   ; End of 4-offset builder.

BUILD_OFFSET_ROW macro                     ; Build one logical row of 28 centered direct-table offsets.
    move.w  a4,d0                          ; Restore the row start U into the running U register.
    move.w  a5,d1                          ; Restore the row start V into the running V register.
    rept    (ROTO_COLUMNS/4)               ; Process the row in 4-texel groups.
        BUILD_OFFSET_GROUP                 ; Build and store one 4-offset group.
    endr                                   ; End of group loop.
    adda.w  d3,a4                          ; Advance the next row start U by the row step.
    suba.w  d2,a5                          ; Advance the next row start V by the row step.
    endm                                   ; End of row builder.

_BuildTextureOffsetsSliceAsm::             ; Build all centered direct-table offsets for one 4-row slice.
    movem.l d2-d7/a4-a5,-(sp)              ; Preserve the callee-saved registers used by the builder.

    move.w  ROTOFRAME_DUDX(a0),d2          ; d2 = DuDx.
    move.w  ROTOFRAME_DVDX(a0),d3          ; d3 = DvDx.
    movea.w ROTOFRAME_STARTU(a0),a4        ; a4 = StartU of the first row in this chunk.
    movea.w ROTOFRAME_STARTV(a0),a5        ; a5 = StartV of the first row in this chunk.

    rept    ROTO_CHUNK_ROWS                ; Build the fixed 4 rows of this slice.
        BUILD_OFFSET_ROW                   ; Build one row of offsets.
    endr                                   ; End of row unroll.

    movem.l (sp)+,d2-d7/a4-a5              ; Restore the preserved registers.
    rts                                    ; Return to C.

RENDER_ONE_DIRECT_OFFSET_D0 macro          ; Render one logical texel from the low word of d0.
    move.w  d0,d7                          ; Copy the prebuilt centered descriptor offset into the scratch register.
    move.l  0(a2,d7.w),d6                  ; Load the direct texel descriptor from the centered 64 KiB table.
    move.w  d6,d7                          ; Copy the green-pack byte offset from the descriptor low word.
    or.w    d4,d7                          ; Add the current previous-green subtable base.
    move.l  0(a3,d7.w),d7                  ; Load the green transition entry for this texel/state pair.
    move.w  d7,d4                          ; Carry the next previous-green subtable base.
    swap    d7                             ; Move the green render word into the low half.
    swap    d6                             ; Move the red/blue base word into the low half.
    or.w    d6,d7                          ; Merge the red/blue base word into the final HAM word.
    endm                                   ; End of d0-based texel renderer.

RENDER_ONE_DIRECT_OFFSET_D1 macro          ; Render one logical texel from the low word of d1.
    move.w  d1,d7                          ; Copy the prebuilt centered descriptor offset into the scratch register.
    move.l  0(a2,d7.w),d6                  ; Load the direct texel descriptor from the centered 64 KiB table.
    move.w  d6,d7                          ; Copy the green-pack byte offset from the descriptor low word.
    or.w    d4,d7                          ; Add the current previous-green subtable base.
    move.l  0(a3,d7.w),d7                  ; Load the green transition entry for this texel/state pair.
    move.w  d7,d4                          ; Carry the next previous-green subtable base.
    swap    d7                             ; Move the green render word into the low half.
    swap    d6                             ; Move the red/blue base word into the low half.
    or.w    d6,d7                          ; Merge the red/blue base word into the final HAM word.
    endm                                   ; End of d1-based texel renderer.

STORE_SWAPPED_GROUP macro                  ; Convert four 16-bit render words into the byte-scrambled temp layout.
    movea.l d6,a5                          ; Save words 3/4 pair in the free address register.
    move.l  d5,d7                          ; Copy words 1/2 pair into the scratch register.
    andi.l  #$ff00ff00,d5                  ; Keep the high bytes from words 1/2.
    lsr.l   #8,d6                          ; Shift words 3/4 so their low bytes line up.
    andi.l  #$00ff00ff,d6                  ; Keep the low bytes from words 3/4.
    or.l    d6,d5                          ; Build the first scrambled longword.
    move.l  d5,(a1)+                       ; Store the first scrambled longword.
    lsl.l   #8,d7                          ; Shift words 1/2 so their low bytes line up.
    andi.l  #$ff00ff00,d7                  ; Keep the shifted bytes from words 1/2.
    move.l  a5,d6                          ; Restore words 3/4 pair from the address register.
    andi.l  #$00ff00ff,d6                  ; Keep the low bytes from words 3/4.
    or.l    d6,d7                          ; Build the second scrambled longword.
    move.l  d7,(a1)+                       ; Store the second scrambled longword.
    endm                                   ; End of byte-scrambling macro.

RENDER_GROUP_FROM_OFFSETS macro            ; Render and pack four logical texels from the offset buffer.
    move.l  (a0)+,d0                       ; Load texture offsets 0 and 1 with one longword read.
    swap    d0                             ; Place texture offset 0 into the low word and offset 1 into the high word.
    move.l  (a0)+,d1                       ; Load texture offsets 2 and 3 with one longword read.
    swap    d1                             ; Place texture offset 2 into the low word and offset 3 into the high word.
    RENDER_ONE_DIRECT_OFFSET_D0              ; Render texel 0 from the low word of d0.
    move.w  d7,d5                          ; Put word 0 into the low half of pair 0/1.
    swap    d5                             ; Move word 0 into the high half of pair 0/1.
    swap    d0                             ; Move texture offset 1 into the low word.
    RENDER_ONE_DIRECT_OFFSET_D0              ; Render texel 1 from the low word of d0.
    move.w  d7,d5                          ; Put word 1 into the low half of pair 0/1.
    RENDER_ONE_DIRECT_OFFSET_D1              ; Render texel 2 from the low word of d1.
    move.w  d7,d6                          ; Put word 2 into the low half of pair 2/3.
    swap    d6                             ; Move word 2 into the high half of pair 2/3.
    movea.l d6,a6                          ; Preserve pair 2/3 because the next renderer reuses d6/d7.
    swap    d1                             ; Move texture offset 3 into the low word.
    RENDER_ONE_DIRECT_OFFSET_D1              ; Render texel 3 from the low word of d1.
    move.l  a6,d6                          ; Restore pair 2/3 from the address register.
    move.w  d7,d6                          ; Put word 3 into the low half of pair 2/3.
    STORE_SWAPPED_GROUP                    ; Emit the two scrambled longwords for this 4-texel group.
    endm                                   ; End of 4-texel renderer.

RENDER_ROW_FROM_OFFSETS macro              ; Render one logical row from prebuilt centered descriptor offsets.
    moveq   #0,d4                          ; Reset the previous-green subtable base to 0 for a new row.
    rept    (ROTO_COLUMNS/4)               ; Process the row in 4-texel groups.
        RENDER_GROUP_FROM_OFFSETS          ; Render one 4-texel group.
    endr                                   ; End of group loop.
    endm                                   ; End of row renderer.

_RenderPhase0TempOffsetSliceAsm::          ; Render one 4-row slice from the centered-offset buffer into the temp buffer.
    movem.l d4-d7/a2-a3/a5-a6,-(sp)        ; Preserve the registers used by the offset-based hot path.

    movea.l _TextureDirectBaseMid,a2       ; a2 = centered direct 32-bit texture descriptor table.
    movea.l _Ham7Phase0GreenPack,a3        ; a3 = green transition table.

    rept    ROTO_CHUNK_ROWS                ; Render the fixed 4 rows of this slice.
        RENDER_ROW_FROM_OFFSETS            ; Render one row from prebuilt offsets.
    endr                                   ; End of row unroll.

    movem.l (sp)+,d4-d7/a2-a3/a5-a6        ; Restore all preserved registers.
    rts                                    ; Return to C.

WaitBlit:                                  ; Wait until the blitter is idle.
.wait:                                     ; Busy-wait loop entry.
    btst    #14,DMACONR_OFF(a6)            ; Test the blitter busy bit.
    bne.s   .wait                          ; Stay here while the blitter is still active.
    rts                                    ; Return when the blitter is idle.

DoExtractRight:                            ; Extract the ascending/right-going planes.
    move.l  #BLIT_EXTRACT_4_RIGHT,BLTCON0_OFF(a6) ; Select the right-going extractor setup.
    move.l  a0,BLTBPTH_OFF(a6)             ; Plane 3: B source starts at temp base.
    movea.l a0,a3                          ; Copy temp base.
    adda.w  #2,a3                          ; A source is shifted by one word.
    move.l  a3,BLTAPTH_OFF(a6)             ; Write A pointer.
    movea.l a1,a3                          ; Copy planar base.
    adda.w  #(ROTO_PLANE_BYTES*3),a3       ; Destination = plane 3 inside the compact screen buffer.
    move.l  a3,BLTDPTH_OFF(a6)             ; Write destination pointer.
    move.w  #ROTO_C2P_BLTSIZE,BLTSIZE_OFF(a6) ; Start full-plane blit for plane 3.
    jsr     WaitBlit                       ; Wait for plane 3 to finish without branch-range limits.

    movea.l a0,a3                          ; Reload temp base for plane 1.
    adda.w  #4,a3                          ; Plane 1: B source starts two words later.
    move.l  a3,BLTBPTH_OFF(a6)             ; Write B pointer.
    adda.w  #2,a3                          ; A source again uses the +2 byte skew.
    move.l  a3,BLTAPTH_OFF(a6)             ; Write A pointer.
    movea.l a1,a3                          ; Reload planar base.
    adda.w  #ROTO_PLANE_BYTES,a3           ; Destination = plane 1.
    move.l  a3,BLTDPTH_OFF(a6)             ; Write destination pointer.
    move.w  #ROTO_C2P_BLTSIZE,BLTSIZE_OFF(a6) ; Start full-plane blit for plane 1.
    jsr     WaitBlit                       ; Wait for plane 1 to finish without branch-range limits.
    rts                                    ; Return to caller.

DoExtractLeft:                             ; Extract the descending/left-going planes.
    move.l  #BLIT_EXTRACT_4_LEFT,BLTCON0_OFF(a6) ; Select the left-going extractor setup.
    movea.l a0,a3                          ; Copy temp base.
    adda.w  #(ROTO_SCREEN_BYTES-8),a3      ; Plane 2: start near the end of the temp buffer.
    move.l  a3,BLTAPTH_OFF(a6)             ; Write A pointer.
    adda.w  #2,a3                          ; B source is the adjacent word.
    move.l  a3,BLTBPTH_OFF(a6)             ; Write B pointer.
    movea.l a1,a3                          ; Copy planar base.
    adda.w  #((ROTO_PLANE_BYTES*3)-2),a3   ; Destination = plane 2 end address.
    move.l  a3,BLTDPTH_OFF(a6)             ; Write destination pointer.
    move.w  #ROTO_C2P_BLTSIZE,BLTSIZE_OFF(a6) ; Start full-plane blit for plane 2.
    jsr     WaitBlit                       ; Wait for plane 2 to finish without branch-range limits.

    movea.l a0,a3                          ; Reload temp base for plane 0.
    adda.w  #(ROTO_SCREEN_BYTES-4),a3      ; Plane 0: start one word earlier than plane 2.
    move.l  a3,BLTAPTH_OFF(a6)             ; Write A pointer.
    adda.w  #2,a3                          ; B source is the adjacent word.
    move.l  a3,BLTBPTH_OFF(a6)             ; Write B pointer.
    movea.l a1,a3                          ; Reload planar base.
    adda.w  #(ROTO_PLANE_BYTES-2),a3       ; Destination = plane 0 end address.
    move.l  a3,BLTDPTH_OFF(a6)             ; Write destination pointer.
    move.w  #ROTO_C2P_BLTSIZE,BLTSIZE_OFF(a6) ; Start full-plane blit for plane 0.
    rts                                    ; Caller may overlap the final blit.

_StartC2PExtractAsm::                      ; Start the full asynchronous extraction path.
    movem.l a3/a6,-(sp)                    ; Preserve scratch address registers.
    lea     CUSTOM_BASE,a6                 ; a6 = custom chip base.
    jsr     WaitBlit                       ; Ensure no previous blit is still running without branch-range limits.
    jsr     DoExtractRight                 ; Extract planes 3 and 1 without branch-range limits.
    jsr     DoExtractLeft                  ; Extract planes 2 and 0 without branch-range limits.
    movem.l (sp)+,a3/a6                    ; Restore registers.
    rts                                    ; Return to C.

_StartC2PPlane3Asm::                       ; Start only the plane 3 extractor pass.
    movem.l a3/a6,-(sp)                    ; Preserve scratch address registers.
    lea     CUSTOM_BASE,a6                 ; a6 = custom chip base.
    move.l  #BLIT_EXTRACT_4_RIGHT,BLTCON0_OFF(a6) ; Select the right-going extractor.
    move.l  a0,BLTBPTH_OFF(a6)             ; B source = temp base.
    movea.l a0,a3                          ; Copy temp base.
    adda.w  #2,a3                          ; A source = temp base + 2.
    move.l  a3,BLTAPTH_OFF(a6)             ; Write A pointer.
    movea.l a1,a3                          ; Copy planar base.
    adda.w  #(ROTO_PLANE_BYTES*3),a3       ; Destination = plane 3.
    move.l  a3,BLTDPTH_OFF(a6)             ; Write destination pointer.
    move.w  #ROTO_C2P_BLTSIZE,BLTSIZE_OFF(a6) ; Start the plane 3 blit.
    movem.l (sp)+,a3/a6                    ; Restore registers.
    rts                                    ; Return immediately.

_StartC2PPlane1Asm::                       ; Start only the plane 1 extractor pass.
    movem.l a3/a6,-(sp)                    ; Preserve scratch address registers.
    lea     CUSTOM_BASE,a6                 ; a6 = custom chip base.
    movea.l a0,a3                          ; Copy temp base.
    adda.w  #4,a3                          ; Plane 1 B source offset.
    move.l  a3,BLTBPTH_OFF(a6)             ; Write B pointer.
    adda.w  #2,a3                          ; Plane 1 A source offset.
    move.l  a3,BLTAPTH_OFF(a6)             ; Write A pointer.
    movea.l a1,a3                          ; Copy planar base.
    adda.w  #ROTO_PLANE_BYTES,a3           ; Destination = plane 1.
    move.l  a3,BLTDPTH_OFF(a6)             ; Write destination pointer.
    move.w  #ROTO_C2P_BLTSIZE,BLTSIZE_OFF(a6) ; Start the plane 1 blit.
    movem.l (sp)+,a3/a6                    ; Restore registers.
    rts                                    ; Return immediately.

_StartC2PPlane2Asm::                       ; Start only the plane 2 extractor pass.
    movem.l a3/a6,-(sp)                    ; Preserve scratch address registers.
    lea     CUSTOM_BASE,a6                 ; a6 = custom chip base.
    move.l  #BLIT_EXTRACT_4_LEFT,BLTCON0_OFF(a6) ; Select the left-going extractor.
    movea.l a0,a3                          ; Copy temp base.
    adda.w  #(ROTO_SCREEN_BYTES-8),a3      ; Plane 2 A source offset.
    move.l  a3,BLTAPTH_OFF(a6)             ; Write A pointer.
    adda.w  #2,a3                          ; Plane 2 B source offset.
    move.l  a3,BLTBPTH_OFF(a6)             ; Write B pointer.
    movea.l a1,a3                          ; Copy planar base.
    adda.w  #((ROTO_PLANE_BYTES*3)-2),a3   ; Destination = plane 2 end address.
    move.l  a3,BLTDPTH_OFF(a6)             ; Write destination pointer.
    move.w  #ROTO_C2P_BLTSIZE,BLTSIZE_OFF(a6) ; Start the plane 2 blit.
    movem.l (sp)+,a3/a6                    ; Restore registers.
    rts                                    ; Return immediately.

_StartC2PPlane0Asm::                       ; Start only the plane 0 extractor pass.
    movem.l a3/a6,-(sp)                    ; Preserve scratch address registers.
    lea     CUSTOM_BASE,a6                 ; a6 = custom chip base.
    movea.l a0,a3                          ; Copy temp base.
    adda.w  #(ROTO_SCREEN_BYTES-4),a3      ; Plane 0 A source offset.
    move.l  a3,BLTAPTH_OFF(a6)             ; Write A pointer.
    adda.w  #2,a3                          ; Plane 0 B source offset.
    move.l  a3,BLTBPTH_OFF(a6)             ; Write B pointer.
    movea.l a1,a3                          ; Copy planar base.
    adda.w  #(ROTO_PLANE_BYTES-2),a3       ; Destination = plane 0 end address.
    move.l  a3,BLTDPTH_OFF(a6)             ; Write destination pointer.
    move.w  #ROTO_C2P_BLTSIZE,BLTSIZE_OFF(a6) ; Start the plane 0 blit.
    movem.l (sp)+,a3/a6                    ; Restore registers.
    rts                                    ; Return immediately.

_RunC2PExtractAsm::                        ; Run the full synchronous extraction path and wait for completion.
    movem.l a3/a6,-(sp)                    ; Preserve scratch address registers.
    lea     CUSTOM_BASE,a6                 ; a6 = custom chip base.
    jsr     WaitBlit                       ; Ensure no previous blit is still running without branch-range limits.
    jsr     DoExtractRight                 ; Extract planes 3 and 1 without branch-range limits.
    jsr     DoExtractLeft                  ; Extract planes 2 and 0 without branch-range limits.
    jsr     WaitBlit                       ; Wait for the final plane 0 blit without branch-range limits.
    movem.l (sp)+,a3/a6                    ; Restore registers.
    rts                                    ; Return to C.
