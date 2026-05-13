; Generated from Rotozoomer_shared_defs.py.
; Shared constants for Rotozoomer.c and Rotozoomer_vasm.s.

HAM_COLUMNS                              equ	56         ; number of HAM cells per row
HAM_ROWS                                 equ	52         ; number of displayed HAM cell rows
HAM_PIXEL_SIZE                           equ	4          ; cell size in display pixels
HAM_DISPLAY_WIDTH                        equ	224        ; visible HAM width in pixels
HAM_DISPLAY_HEIGHT                       equ	208        ; visible HAM height in pixels
HAM_FETCH_BYTES                          equ	28         ; bytes per rendered bitplane row
HAM_PLANE_BYTES                          equ	1456       ; bytes per displayed HAM bitplane
HAM_FRAME_COUNT                          equ	256        ; number of animation frames
HAM_LIVE_ROWS                            equ	2          ; number of runtime-rendered core cell rows
HAM_TEMPORAL_START_ROW                   equ	2          ; first temporal dynamic row
HAM_TEMPORAL_ROWS                        equ	26         ; number of temporal dynamic rows
HAM_TEMPORAL_HALF_ROWS                   equ	13         ; number of rows in one temporal half
HAM_HALFRATE_START_ROW                   equ	28         ; first half-rate cached row
HAM_SLOW_START_ROW                       equ	49         ; first direct slow-cache row
HAM_CACHE_START_ROW                      equ	52         ; cache run disabled after display area
HAM_SLOW_ROWS                            equ	3          ; number of direct slow-cache rows per frame
HAM_CACHE_ROWS                           equ	0          ; no full-rate cached bottom rows
HAM_DYNAMIC_ROWS                         equ	28         ; compact live and temporal rows per frame
HAM_DYNAMIC_PLANE_BYTES                  equ	784        ; bytes per compact dynamic bitplane
HAM_DYNAMIC_BITMAP_BYTES                 equ	3136       ; bytes per compact dynamic bitmap
HAM_ROW_CACHE_PLANE_BYTES                equ	0          ; disabled full-rate cache plane bytes
HAM_ROW_CACHE_FRAME_BYTES                equ	0          ; disabled full-rate cache frame bytes
HAM_ROW_CACHE_BYTES                      equ	0          ; disabled full-rate cache bytes
HAM_TEMPORAL_ROW_BYTES                   equ	728        ; bytes per temporal bitplane area
HAM_HALFRATE_ROWS                        equ	21         ; number of half-rate rows per cached frame
HAM_HALFRATE_FRAME_COUNT                 equ	128        ; number of cached half-rate frames
HAM_HALFRATE_PLANE_BYTES                 equ	588        ; bytes per half-rate compact bitplane
HAM_HALFRATE_ROW_CACHE_PLANE_BYTES       equ	588        ; bytes per half-rate cache bitplane
HAM_HALFRATE_ROW_CACHE_FRAME_BYTES       equ	2352       ; bytes per half-rate cache frame
HAM_HALFRATE_ROW_CACHE_BYTES             equ	301056     ; bytes for all half-rate cache frames
HAM_HALFRATE_POINTER_WORDS               equ	8          ; words per half-rate pointer frame
HAM_HALFRATE_POINTER_FRAME_BYTES         equ	16         ; bytes per half-rate pointer frame
HAM_HALFRATE_POINTER_BYTES               equ	2048       ; bytes for all half-rate pointer frames
HAM_SLOW_PLANE_BYTES                     equ	84         ; bytes per slow compact bitplane
HAM_SLOW_ROW_CACHE_PLANE_BYTES           equ	84         ; bytes per slow cache bitplane
HAM_SLOW_ROW_CACHE_FRAME_BYTES           equ	336        ; bytes per slow cache frame
HAM_SLOW_ROW_CACHE_BYTES                 equ	86016      ; bytes for all slow cache frames
HAM_DYNAMIC_BUFFER_BYTES                 equ	6272       ; bytes for both dynamic buffers
HAM_TEMPORAL_UPPER_DEST_OFFSET           equ	56         ; compact row 2 byte offset in dynamic planes
HAM_TEMPORAL_LOWER_DEST_OFFSET           equ	420        ; compact lower temporal-half byte offset in dynamic planes
HAM_COPPER_BPLPTR_WORD                   equ	23         ; value slot for initial dynamic row pointers
HAM_COPPER_HALFRATE_BPLPTR_WORD          equ	397        ; value slot for half-rate row pointers
HAM_COPPER_HALFRATE_BPLPTR_BYTES         equ	794        ; byte slot for half-rate row pointers
HAM_COPPER_SLOW_BPLPTR_WORD              equ	657        ; value slot for direct slow-cache row pointers
HAM_COPPER_SLOW_BPLPTR_BYTES             equ	1314       ; byte slot for direct slow-cache row pointers
HAM_COPPER_CACHE_BPLPTR_WORD             equ	0          ; full-rate cache pointer slot unused
HAM_COPPER_CACHE_BPLPTR_BYTES            equ	0          ; full-rate cache pointer byte slot unused
HAM_COPPER_WORDS                         equ	698        ; copper list words per buffer
HAM_COPPER_BYTES                         equ	1396       ; copper list bytes per buffer
HAM_CHIP_BLOCK_BYTES                     equ	9064       ; dynamic buffers plus double copper list block bytes
HAM_TOTAL_CHIP_BYTES                     equ	396136     ; total chip bytes allocated by the effect
HAM_HALF_COLUMNS                         equ	28         ; half of the HAM cell columns
HAM_HALF_ROWS                            equ	26         ; half of the HAM cell rows
HAM_SCREEN_WIDTH                         equ	320        ; target screen width
HAM_SCREEN_HEIGHT                        equ	256        ; target screen height
HAM_START_X                              equ	48         ; HAM display x position
HAM_PAL_VPOS_TOP                         equ	$002C      ; PAL display top line
HAM_VPOS_START                           equ	$0044      ; first visible HAM display line
HAM_VPOS_STOP                            equ	$0114      ; first line after HAM display
HAM_COPPER_WRAP_ROW                      equ	47         ; row where copper waits cross line 255
HAM_DIWSTRT                              equ	$4481      ; display window start register value
HAM_DIWSTOP                              equ	$14C1      ; display window stop register value
HAM_DDF_SHIFT_BYTES                      equ	6          ; display fetch byte shift
HAM_DDFSTRT                              equ	$0050      ; data fetch start register value
HAM_DDFSTOP                              equ	$00B8      ; data fetch stop register value
HAM_REPEAT_MOD                           equ	$FFE4      ; modulo for repeating a 4-line cell row
HAM_ADVANCE_MOD                          equ	0          ; modulo for advancing to the next cell row
HAM_DISPLAY_BPU                          equ	7          ; bitplanes used by the HAM display
HAM_CONTROL_WORD_P5                      equ	$3333      ; BPL5DAT HAM control pattern
HAM_CONTROL_WORD_P6                      equ	$6666      ; BPL6DAT HAM control pattern
HAM_CORE_DONE_LOW                        equ	$4C        ; low byte after dynamic rows 0-1 are off-screen
HAM_TEMPORAL_UPPER_DONE_LOW              equ	$80        ; low byte after upper temporal rows are off-screen
HAM_TEMPORAL_DONE_LOW                    equ	$B4        ; low byte after temporal rows are off-screen
HAM_SLOW_DONE_LOW                        equ	$14        ; low byte after direct slow-cache rows are safely past
HAM_ZOOM_BASE                            equ	256        ; base zoom factor
HAM_ZOOM_AMPLITUDE                       equ	96         ; zoom sine amplitude
HAM_ANGLE_PHASE_STEP                     equ	2          ; phase step per frame
HAM_CENTER_U                             equ	$4000      ; texture center U
HAM_CENTER_V                             equ	$4000      ; texture center V
BLTPRI_SET                               equ	$8400      ; set blitter priority while CPU waits
BLTPRI_CLR                               equ	$0400      ; clear blitter priority before CPU overlap
BLIT_TEMPORAL_WIDE_SIZE                  equ	$0100      ; 4 planes, 64-word chunk, width zero encodes 64
BLIT_TEMPORAL_TAIL_SIZE                  equ	$0136      ; 4 planes, temporal tail chunk
BLIT_TEMPORAL_WIDE_BYTES                 equ	128        ; byte count of one 64-word temporal chunk
BLIT_TEMPORAL_TAIL_BYTES                 equ	108        ; byte count of the final temporal chunk
BLIT_TEMPORAL_WIDE_MOD                   equ	656        ; next plane after wide chunk
BLIT_TEMPORAL_TAIL_MOD                   equ	676        ; next plane after tail chunk
BLIT_TEMPORAL_WIDE_MOD_LONG              equ	$02900290  ; source and destination wide modulos
BLIT_TEMPORAL_TAIL_MOD_LONG              equ	$02A402A4  ; source and destination tail modulos
