; Generated from Rotozoomer_shared_defs.py.
; Shared constants for Rotozoomer.c and Rotozoomer_vasm.s.

HAM_COLUMNS                                      equ	56         ; number of HAM cells per row
HAM_ROWS                                         equ	52         ; number of displayed HAM cell rows
HAM_PIXEL_SIZE                                   equ	4          ; cell size in display pixels
HAM_DISPLAY_WIDTH                                equ	224        ; visible HAM width in pixels
HAM_DISPLAY_HEIGHT                               equ	208        ; visible HAM height in pixels
HAM_FETCH_BYTES                                  equ	28         ; bytes per rendered bitplane row
HAM_FRAME_COUNT                                  equ	256        ; number of animation frames
HAM_FRAME_PARAM_BYTES                            equ	12         ; bytes per frame-parameter entry
HAM_LIVE_ROWS                                    equ	2          ; number of runtime-rendered core cell rows
HAM_TEMPORAL_START_ROW                           equ	2          ; first temporal dynamic row
HAM_TEMPORAL_ROWS                                equ	16         ; number of temporal dynamic rows
HAM_TEMPORAL_HALF_ROWS                           equ	8          ; number of rows in one temporal half
HAM_TEMPORAL_LOWER_START_ROW                     equ	10         ; first row of the lower temporal half
HAM_HALFRATE_START_ROW                           equ	18         ; first half-rate cached row
HAM_DYNAMIC_ROWS                                 equ	18         ; compact live and temporal rows per frame
HAM_DYNAMIC_PLANE_BYTES                          equ	504        ; bytes per compact dynamic bitplane
HAM_DYNAMIC_BITMAP_BYTES                         equ	2016       ; bytes per compact dynamic bitmap
HAM_HALFRATE_ROWS                                equ	34         ; number of half-rate rows per cached frame
HAM_HALFRATE_ROW_CACHE_PLANE_BYTES               equ	952        ; bytes per half-rate cache bitplane
HAM_HALFRATE_ROW_CACHE_FRAME_BYTES               equ	3808       ; bytes per half-rate cache frame
HAM_HALFRATE_ROW_CACHE_BYTES                     equ	487424     ; bytes for all half-rate cache frames
HAM_TEMPORAL_UPPER_DEST_OFFSET                   equ	56         ; compact row 2 byte offset in dynamic planes
HAM_TEMPORAL_LOWER_DEST_OFFSET                   equ	280        ; compact lower temporal-half byte offset in dynamic planes
HAM_AGA_CONTROL_PLANE_BYTES                      equ	1456       ; bytes per AGA fixed HAM-control plane
HAM_AGA_CONTROL_PLANES_BYTES                     equ	2912       ; bytes for both AGA fixed HAM-control planes
HAM_AGA_BPLCON3_RESET                            equ	$0000      ; AGA BPLCON3 palette-bank and LOCT reset
HAM_AGA_BPLCON4_RESET                            equ	$0000      ; AGA BPLCON4 bitplane XOR reset
HAM_AGA_FMODE_RESET                              equ	$0000      ; AGA 16-bit compatible fetch mode
HAM_AGA_BPLCON3_LOCT                             equ	$0200      ; AGA low-order color-table write select
HAM_AGA_DISPLAY_BPU                              equ	6          ; AGA normal HAM6 bitplane count
HAM_OCS_COPPER_BPLPTR_WORD                       equ	23         ; OCS value slot for initial dynamic row pointers
HAM_OCS_COPPER_TEMPORAL_UPPER_BPLPTR_WORD        equ	53         ; OCS value slot for upper temporal row pointers
HAM_OCS_COPPER_TEMPORAL_UPPER_BPLPTR_BYTES       equ	106        ; OCS byte slot for upper temporal row pointers
HAM_OCS_COPPER_TEMPORAL_LOWER_BPLPTR_WORD        equ	155        ; OCS value slot for lower temporal row pointers
HAM_OCS_COPPER_TEMPORAL_LOWER_BPLPTR_BYTES       equ	310        ; OCS byte slot for lower temporal row pointers
HAM_OCS_COPPER_HALFRATE_BPLPTR_WORD              equ	257        ; OCS value slot for half-rate row pointers
HAM_OCS_COPPER_HALFRATE_BPLPTR_BYTES             equ	514        ; OCS byte slot for half-rate row pointers
HAM_OCS_COPPER_WORDS                             equ	672        ; OCS copper list words
HAM_OCS_COPPER_BYTES                             equ	1344       ; OCS copper list bytes
HAM_AGA_COPPER_BPLPTR_WORD                       equ	29         ; AGA value slot for initial dynamic row pointers
HAM_AGA_COPPER_TEMPORAL_UPPER_BPLPTR_WORD        equ	67         ; AGA value slot for upper temporal row pointers
HAM_AGA_COPPER_TEMPORAL_UPPER_BPLPTR_BYTES       equ	134        ; AGA byte slot for upper temporal row pointers
HAM_AGA_COPPER_TEMPORAL_LOWER_BPLPTR_WORD        equ	177        ; AGA value slot for lower temporal row pointers
HAM_AGA_COPPER_TEMPORAL_LOWER_BPLPTR_BYTES       equ	354        ; AGA byte slot for lower temporal row pointers
HAM_AGA_COPPER_HALFRATE_BPLPTR_WORD              equ	287        ; AGA value slot for half-rate row pointers
HAM_AGA_COPPER_HALFRATE_BPLPTR_BYTES             equ	574        ; AGA byte slot for half-rate row pointers
HAM_AGA_COPPER_WORDS                             equ	710        ; AGA copper list words
HAM_AGA_COPPER_BYTES                             equ	1420       ; AGA copper list bytes
HAM_COPPER_WORDS                                 equ	710        ; maximum copper list words per buffer
HAM_COPPER_BYTES                                 equ	1420       ; maximum copper list bytes per buffer
HAM_CHIP_BLOCK_BYTES                             equ	6872       ; dynamic buffers plus double copper list block bytes
HAM_HALF_COLUMNS                                 equ	28         ; half of the HAM cell columns
HAM_HALF_ROWS                                    equ	26         ; half of the HAM cell rows
HAM_VPOS_START                                   equ	$0044      ; first visible HAM display line
HAM_DIWSTRT                                      equ	$4481      ; display window start register value
HAM_DIWSTOP                                      equ	$14C1      ; display window stop register value
HAM_DDFSTRT                                      equ	$0050      ; data fetch start register value
HAM_DDFSTOP                                      equ	$00B8      ; data fetch stop register value
HAM_REPEAT_MOD                                   equ	$FFE4      ; modulo for repeating a 4-line cell row
HAM_ADVANCE_MOD                                  equ	0          ; modulo for advancing to the next cell row
HAM_DISPLAY_BPU                                  equ	7          ; OCS BPLDAT-quirk bitplane count
HAM_CONTROL_WORD_P5                              equ	$3333      ; BPL5DAT/HAM control plane 5 pattern
HAM_CONTROL_WORD_P6                              equ	$6666      ; BPL6DAT/HAM control plane 6 pattern
HAM_CORE_DONE_LOW                                equ	$4C        ; low byte after dynamic rows 0-1 are off-screen
HAM_TEMPORAL_UPPER_DONE_LOW                      equ	$6C        ; low byte after upper temporal rows are off-screen
HAM_TEMPORAL_DONE_LOW                            equ	$8C        ; low byte after temporal rows are off-screen
HAM_ZOOM_BASE                                    equ	256        ; base zoom factor
HAM_ZOOM_AMPLITUDE                               equ	96         ; zoom sine amplitude
HAM_ANGLE_PHASE_STEP                             equ	1          ; phase step per frame
HAM_CENTER_U                                     equ	$4000      ; texture center U
HAM_CENTER_V                                     equ	$4000      ; texture center V
