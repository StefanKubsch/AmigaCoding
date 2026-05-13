#!/usr/bin/env python3
# Generates constants shared by the C and vasm parts of the Rotozoomer.

from pathlib import Path

HAM_COLUMNS = 56
HAM_ROWS = 52
HAM_PIXEL_SIZE = 4
HAM_FETCH_BYTES = (HAM_COLUMNS * HAM_PIXEL_SIZE) >> 3
HAM_FRAME_COUNT = 256
HAM_LIVE_ROWS = 2
HAM_TEMPORAL_START_ROW = 2
HAM_TEMPORAL_ROWS = 26
HAM_TEMPORAL_HALF_ROWS = HAM_TEMPORAL_ROWS // 2
HAM_HALFRATE_START_ROW = HAM_TEMPORAL_START_ROW + HAM_TEMPORAL_ROWS
HAM_SLOW_START_ROW = 49
HAM_CACHE_START_ROW = 52
HAM_SLOW_ROWS = HAM_ROWS - HAM_SLOW_START_ROW
HAM_CACHE_ROWS = 0
HAM_DYNAMIC_ROWS = HAM_TEMPORAL_START_ROW + HAM_TEMPORAL_ROWS
HAM_HALFRATE_ROWS = HAM_SLOW_START_ROW - HAM_HALFRATE_START_ROW
HAM_HALFRATE_FRAME_COUNT = HAM_FRAME_COUNT // 2
HAM_SCREEN_WIDTH = 320
HAM_SCREEN_HEIGHT = 256
HAM_DISPLAY_WIDTH = HAM_COLUMNS * HAM_PIXEL_SIZE
HAM_DISPLAY_HEIGHT = HAM_ROWS * HAM_PIXEL_SIZE
HAM_START_X = (HAM_SCREEN_WIDTH - HAM_DISPLAY_WIDTH) // 2
HAM_PAL_VPOS_TOP = 0x2C
HAM_VPOS_START = HAM_PAL_VPOS_TOP + ((HAM_SCREEN_HEIGHT - HAM_DISPLAY_HEIGHT) // 2)
HAM_VPOS_STOP = HAM_VPOS_START + HAM_DISPLAY_HEIGHT
HAM_DDF_SHIFT_BYTES = HAM_START_X >> 3

HAM_PLANE_BYTES = HAM_FETCH_BYTES * HAM_ROWS
HAM_DYNAMIC_PLANE_BYTES = HAM_FETCH_BYTES * HAM_DYNAMIC_ROWS
HAM_DYNAMIC_BITMAP_BYTES = HAM_DYNAMIC_PLANE_BYTES * 4
HAM_ROW_CACHE_PLANE_BYTES = HAM_FETCH_BYTES * HAM_CACHE_ROWS
HAM_ROW_CACHE_FRAME_BYTES = HAM_ROW_CACHE_PLANE_BYTES * 4
HAM_ROW_CACHE_BYTES = HAM_ROW_CACHE_FRAME_BYTES * HAM_FRAME_COUNT
HAM_TEMPORAL_ROW_BYTES = HAM_FETCH_BYTES * HAM_TEMPORAL_ROWS
HAM_HALFRATE_PLANE_BYTES = HAM_FETCH_BYTES * HAM_HALFRATE_ROWS
HAM_HALFRATE_ROW_CACHE_PLANE_BYTES = HAM_HALFRATE_PLANE_BYTES
HAM_HALFRATE_ROW_CACHE_FRAME_BYTES = HAM_HALFRATE_ROW_CACHE_PLANE_BYTES * 4
HAM_HALFRATE_ROW_CACHE_BYTES = HAM_HALFRATE_ROW_CACHE_FRAME_BYTES * HAM_HALFRATE_FRAME_COUNT
HAM_HALFRATE_POINTER_WORDS = 8
HAM_HALFRATE_POINTER_FRAME_BYTES = HAM_HALFRATE_POINTER_WORDS * 2
HAM_HALFRATE_POINTER_BYTES = HAM_HALFRATE_POINTER_FRAME_BYTES * HAM_HALFRATE_FRAME_COUNT
HAM_SLOW_PLANE_BYTES = HAM_FETCH_BYTES * HAM_SLOW_ROWS
HAM_SLOW_ROW_CACHE_PLANE_BYTES = HAM_SLOW_PLANE_BYTES
HAM_SLOW_ROW_CACHE_FRAME_BYTES = HAM_SLOW_ROW_CACHE_PLANE_BYTES * 4
HAM_SLOW_ROW_CACHE_BYTES = HAM_SLOW_ROW_CACHE_FRAME_BYTES * HAM_FRAME_COUNT
HAM_DYNAMIC_BUFFER_BYTES = HAM_DYNAMIC_BITMAP_BYTES * 2
HAM_TEMPORAL_UPPER_DEST_OFFSET = HAM_TEMPORAL_START_ROW * HAM_FETCH_BYTES
HAM_TEMPORAL_LOWER_DEST_OFFSET = (HAM_TEMPORAL_START_ROW + HAM_TEMPORAL_HALF_ROWS) * HAM_FETCH_BYTES


def copper_layout():
    index = 0
    wrapped = False

    def append_wait(vpos):
        nonlocal index, wrapped
        if (vpos > 0x00FF) and not wrapped:
            index += 2
            wrapped = True
        index += 2

    def append_modulo():
        nonlocal index
        index += 4

    def append_bplptr_slots():
        nonlocal index
        index += 16

    index += 8                         # DIW/DDF registers
    index += 10                        # BPLCON and modulo registers
    index += 4                         # HAM control words

    bplptr_word = index + 1
    append_bplptr_slots()
    index += 32                        # COLOR00-COLOR15

    for row in range(HAM_HALFRATE_START_ROW - 1):
        append_wait(HAM_VPOS_START + (row * HAM_PIXEL_SIZE) + (HAM_PIXEL_SIZE - 1))
        append_modulo()
        append_wait(HAM_VPOS_START + ((row + 1) * HAM_PIXEL_SIZE))
        append_modulo()

    append_wait(HAM_VPOS_START + (HAM_HALFRATE_START_ROW * HAM_PIXEL_SIZE))
    halfrate_bplptr_word = index + 1
    append_bplptr_slots()

    for row in range(HAM_HALFRATE_START_ROW, HAM_SLOW_START_ROW - 1):
        append_wait(HAM_VPOS_START + (row * HAM_PIXEL_SIZE) + (HAM_PIXEL_SIZE - 1))
        append_modulo()
        append_wait(HAM_VPOS_START + ((row + 1) * HAM_PIXEL_SIZE))
        append_modulo()

    append_wait(HAM_VPOS_START + (HAM_SLOW_START_ROW * HAM_PIXEL_SIZE))
    slow_bplptr_word = index + 1
    append_bplptr_slots()

    for row in range(HAM_SLOW_START_ROW, HAM_CACHE_START_ROW - 1):
        append_wait(HAM_VPOS_START + (row * HAM_PIXEL_SIZE) + (HAM_PIXEL_SIZE - 1))
        append_modulo()
        append_wait(HAM_VPOS_START + ((row + 1) * HAM_PIXEL_SIZE))
        append_modulo()

    index += 2                         # copper end marker
    return bplptr_word, halfrate_bplptr_word, slow_bplptr_word, index


HAM_COPPER_BPLPTR_WORD, HAM_COPPER_HALFRATE_BPLPTR_WORD, HAM_COPPER_SLOW_BPLPTR_WORD, HAM_COPPER_WORDS = copper_layout()
HAM_COPPER_CACHE_BPLPTR_WORD = 0
HAM_COPPER_BYTES = HAM_COPPER_WORDS * 2
HAM_CHIP_BLOCK_BYTES = HAM_DYNAMIC_BUFFER_BYTES + (HAM_COPPER_BYTES * 2)
HAM_TOTAL_CHIP_BYTES = HAM_HALFRATE_ROW_CACHE_BYTES + HAM_SLOW_ROW_CACHE_BYTES + HAM_CHIP_BLOCK_BYTES

BLIT_TEMPORAL_WIDE_BYTES = 128
BLIT_TEMPORAL_WIDE_WORDS = 0
BLIT_TEMPORAL_HALF_BYTES = HAM_FETCH_BYTES * HAM_TEMPORAL_HALF_ROWS
BLIT_TEMPORAL_TAIL_BYTES = BLIT_TEMPORAL_HALF_BYTES - (BLIT_TEMPORAL_WIDE_BYTES * 2)
BLIT_TEMPORAL_TAIL_WORDS = BLIT_TEMPORAL_TAIL_BYTES // 2

DEFS = [
    ("HAM_COLUMNS", HAM_COLUMNS, "number of HAM cells per row", "dec"),
    ("HAM_ROWS", HAM_ROWS, "number of displayed HAM cell rows", "dec"),
    ("HAM_PIXEL_SIZE", HAM_PIXEL_SIZE, "cell size in display pixels", "dec"),
    ("HAM_DISPLAY_WIDTH", HAM_DISPLAY_WIDTH, "visible HAM width in pixels", "dec"),
    ("HAM_DISPLAY_HEIGHT", HAM_DISPLAY_HEIGHT, "visible HAM height in pixels", "dec"),
    ("HAM_FETCH_BYTES", HAM_FETCH_BYTES, "bytes per rendered bitplane row", "dec"),
    ("HAM_PLANE_BYTES", HAM_PLANE_BYTES, "bytes per displayed HAM bitplane", "dec"),
    ("HAM_FRAME_COUNT", HAM_FRAME_COUNT, "number of animation frames", "dec"),
    ("HAM_LIVE_ROWS", HAM_LIVE_ROWS, "number of runtime-rendered core cell rows", "dec"),
    ("HAM_TEMPORAL_START_ROW", HAM_TEMPORAL_START_ROW, "first temporal dynamic row", "dec"),
    ("HAM_TEMPORAL_ROWS", HAM_TEMPORAL_ROWS, "number of temporal dynamic rows", "dec"),
    ("HAM_TEMPORAL_HALF_ROWS", HAM_TEMPORAL_HALF_ROWS, "number of rows in one temporal half", "dec"),
    ("HAM_HALFRATE_START_ROW", HAM_HALFRATE_START_ROW, "first half-rate cached row", "dec"),
    ("HAM_SLOW_START_ROW", HAM_SLOW_START_ROW, "first direct slow-cache row", "dec"),
    ("HAM_CACHE_START_ROW", HAM_CACHE_START_ROW, "cache run disabled after display area", "dec"),
    ("HAM_SLOW_ROWS", HAM_SLOW_ROWS, "number of direct slow-cache rows per frame", "dec"),
    ("HAM_CACHE_ROWS", HAM_CACHE_ROWS, "no full-rate cached bottom rows", "dec"),
    ("HAM_DYNAMIC_ROWS", HAM_DYNAMIC_ROWS, "compact live and temporal rows per frame", "dec"),
    ("HAM_DYNAMIC_PLANE_BYTES", HAM_DYNAMIC_PLANE_BYTES, "bytes per compact dynamic bitplane", "dec"),
    ("HAM_DYNAMIC_BITMAP_BYTES", HAM_DYNAMIC_BITMAP_BYTES, "bytes per compact dynamic bitmap", "dec"),
    ("HAM_ROW_CACHE_PLANE_BYTES", HAM_ROW_CACHE_PLANE_BYTES, "disabled full-rate cache plane bytes", "dec"),
    ("HAM_ROW_CACHE_FRAME_BYTES", HAM_ROW_CACHE_FRAME_BYTES, "disabled full-rate cache frame bytes", "dec"),
    ("HAM_ROW_CACHE_BYTES", HAM_ROW_CACHE_BYTES, "disabled full-rate cache bytes", "dec"),
    ("HAM_TEMPORAL_ROW_BYTES", HAM_TEMPORAL_ROW_BYTES, "bytes per temporal bitplane area", "dec"),
    ("HAM_HALFRATE_ROWS", HAM_HALFRATE_ROWS, "number of half-rate rows per cached frame", "dec"),
    ("HAM_HALFRATE_FRAME_COUNT", HAM_HALFRATE_FRAME_COUNT, "number of cached half-rate frames", "dec"),
    ("HAM_HALFRATE_PLANE_BYTES", HAM_HALFRATE_PLANE_BYTES, "bytes per half-rate compact bitplane", "dec"),
    ("HAM_HALFRATE_ROW_CACHE_PLANE_BYTES", HAM_HALFRATE_ROW_CACHE_PLANE_BYTES, "bytes per half-rate cache bitplane", "dec"),
    ("HAM_HALFRATE_ROW_CACHE_FRAME_BYTES", HAM_HALFRATE_ROW_CACHE_FRAME_BYTES, "bytes per half-rate cache frame", "dec"),
    ("HAM_HALFRATE_ROW_CACHE_BYTES", HAM_HALFRATE_ROW_CACHE_BYTES, "bytes for all half-rate cache frames", "dec"),
    ("HAM_HALFRATE_POINTER_WORDS", HAM_HALFRATE_POINTER_WORDS, "words per half-rate pointer frame", "dec"),
    ("HAM_HALFRATE_POINTER_FRAME_BYTES", HAM_HALFRATE_POINTER_FRAME_BYTES, "bytes per half-rate pointer frame", "dec"),
    ("HAM_HALFRATE_POINTER_BYTES", HAM_HALFRATE_POINTER_BYTES, "bytes for all half-rate pointer frames", "dec"),
    ("HAM_SLOW_PLANE_BYTES", HAM_SLOW_PLANE_BYTES, "bytes per slow compact bitplane", "dec"),
    ("HAM_SLOW_ROW_CACHE_PLANE_BYTES", HAM_SLOW_ROW_CACHE_PLANE_BYTES, "bytes per slow cache bitplane", "dec"),
    ("HAM_SLOW_ROW_CACHE_FRAME_BYTES", HAM_SLOW_ROW_CACHE_FRAME_BYTES, "bytes per slow cache frame", "dec"),
    ("HAM_SLOW_ROW_CACHE_BYTES", HAM_SLOW_ROW_CACHE_BYTES, "bytes for all slow cache frames", "dec"),
    ("HAM_DYNAMIC_BUFFER_BYTES", HAM_DYNAMIC_BUFFER_BYTES, "bytes for both dynamic buffers", "dec"),
    ("HAM_TEMPORAL_UPPER_DEST_OFFSET", HAM_TEMPORAL_UPPER_DEST_OFFSET, "compact row 2 byte offset in dynamic planes", "dec"),
    ("HAM_TEMPORAL_LOWER_DEST_OFFSET", HAM_TEMPORAL_LOWER_DEST_OFFSET, "compact lower temporal-half byte offset in dynamic planes", "dec"),
    ("HAM_COPPER_BPLPTR_WORD", HAM_COPPER_BPLPTR_WORD, "value slot for initial dynamic row pointers", "dec"),
    ("HAM_COPPER_HALFRATE_BPLPTR_WORD", HAM_COPPER_HALFRATE_BPLPTR_WORD, "value slot for half-rate row pointers", "dec"),
    ("HAM_COPPER_HALFRATE_BPLPTR_BYTES", HAM_COPPER_HALFRATE_BPLPTR_WORD * 2, "byte slot for half-rate row pointers", "dec"),
    ("HAM_COPPER_SLOW_BPLPTR_WORD", HAM_COPPER_SLOW_BPLPTR_WORD, "value slot for direct slow-cache row pointers", "dec"),
    ("HAM_COPPER_SLOW_BPLPTR_BYTES", HAM_COPPER_SLOW_BPLPTR_WORD * 2, "byte slot for direct slow-cache row pointers", "dec"),
    ("HAM_COPPER_CACHE_BPLPTR_WORD", HAM_COPPER_CACHE_BPLPTR_WORD, "full-rate cache pointer slot unused", "dec"),
    ("HAM_COPPER_CACHE_BPLPTR_BYTES", HAM_COPPER_CACHE_BPLPTR_WORD * 2, "full-rate cache pointer byte slot unused", "dec"),
    ("HAM_COPPER_WORDS", HAM_COPPER_WORDS, "copper list words per buffer", "dec"),
    ("HAM_COPPER_BYTES", HAM_COPPER_BYTES, "copper list bytes per buffer", "dec"),
    ("HAM_CHIP_BLOCK_BYTES", HAM_CHIP_BLOCK_BYTES, "dynamic buffers plus double copper list block bytes", "dec"),
    ("HAM_TOTAL_CHIP_BYTES", HAM_TOTAL_CHIP_BYTES, "total chip bytes allocated by the effect", "dec"),
    ("HAM_HALF_COLUMNS", HAM_COLUMNS // 2, "half of the HAM cell columns", "dec"),
    ("HAM_HALF_ROWS", HAM_ROWS // 2, "half of the HAM cell rows", "dec"),
    ("HAM_SCREEN_WIDTH", HAM_SCREEN_WIDTH, "target screen width", "dec"),
    ("HAM_SCREEN_HEIGHT", HAM_SCREEN_HEIGHT, "target screen height", "dec"),
    ("HAM_START_X", HAM_START_X, "HAM display x position", "dec"),
    ("HAM_PAL_VPOS_TOP", HAM_PAL_VPOS_TOP, "PAL display top line", "hex4"),
    ("HAM_VPOS_START", HAM_VPOS_START, "first visible HAM display line", "hex4"),
    ("HAM_VPOS_STOP", HAM_VPOS_STOP, "first line after HAM display", "hex4"),
    ("HAM_COPPER_WRAP_ROW", ((0x0100 - HAM_VPOS_START) + HAM_PIXEL_SIZE - 1) // HAM_PIXEL_SIZE, "row where copper waits cross line 255", "dec"),
    ("HAM_DIWSTRT", ((HAM_VPOS_START & 0xFF) << 8) | 0x0081, "display window start register value", "hex4"),
    ("HAM_DIWSTOP", ((HAM_VPOS_STOP & 0xFF) << 8) | 0x00C1, "display window stop register value", "hex4"),
    ("HAM_DDF_SHIFT_BYTES", HAM_DDF_SHIFT_BYTES, "display fetch byte shift", "dec"),
    ("HAM_DDFSTRT", 0x0038 + (HAM_DDF_SHIFT_BYTES * 4), "data fetch start register value", "hex4"),
    ("HAM_DDFSTOP", 0x00D0 - (HAM_DDF_SHIFT_BYTES * 4), "data fetch stop register value", "hex4"),
    ("HAM_REPEAT_MOD", (-HAM_FETCH_BYTES) & 0xFFFF, "modulo for repeating a 4-line cell row", "hex4"),
    ("HAM_ADVANCE_MOD", 0, "modulo for advancing to the next cell row", "dec"),
    ("HAM_DISPLAY_BPU", 7, "bitplanes used by the HAM display", "dec"),
    ("HAM_CONTROL_WORD_P5", 0x3333, "BPL5DAT HAM control pattern", "hex4"),
    ("HAM_CONTROL_WORD_P6", 0x6666, "BPL6DAT HAM control pattern", "hex4"),
    ("HAM_CORE_DONE_LOW", (HAM_VPOS_START + (HAM_LIVE_ROWS * HAM_PIXEL_SIZE)) & 0xFF, "low byte after dynamic rows 0-1 are off-screen", "hex2"),
    ("HAM_TEMPORAL_UPPER_DONE_LOW", (HAM_VPOS_START + ((HAM_TEMPORAL_START_ROW + HAM_TEMPORAL_HALF_ROWS) * HAM_PIXEL_SIZE)) & 0xFF, "low byte after upper temporal rows are off-screen", "hex2"),
    ("HAM_TEMPORAL_DONE_LOW", (HAM_VPOS_START + ((HAM_TEMPORAL_START_ROW + HAM_TEMPORAL_ROWS) * HAM_PIXEL_SIZE)) & 0xFF, "low byte after temporal rows are off-screen", "hex2"),
    ("HAM_SLOW_DONE_LOW", (HAM_VPOS_START + (HAM_ROWS * HAM_PIXEL_SIZE)) & 0xFF, "low byte after direct slow-cache rows are safely past", "hex2"),
    ("HAM_ZOOM_BASE", 256, "base zoom factor", "dec"),
    ("HAM_ZOOM_AMPLITUDE", 96, "zoom sine amplitude", "dec"),
    ("HAM_ANGLE_PHASE_STEP", 2, "phase step per frame", "dec"),
    ("HAM_CENTER_U", 0x4000, "texture center U", "hex4"),
    ("HAM_CENTER_V", 0x4000, "texture center V", "hex4"),
    ("BLTPRI_SET", 0x8400, "set blitter priority while CPU waits", "hex4"),
    ("BLTPRI_CLR", 0x0400, "clear blitter priority before CPU overlap", "hex4"),
    ("BLIT_TEMPORAL_WIDE_SIZE", (4 << 6) | BLIT_TEMPORAL_WIDE_WORDS, "4 planes, 64-word chunk, width zero encodes 64", "hex4"),
    ("BLIT_TEMPORAL_TAIL_SIZE", (4 << 6) | BLIT_TEMPORAL_TAIL_WORDS, "4 planes, temporal tail chunk", "hex4"),
    ("BLIT_TEMPORAL_WIDE_BYTES", BLIT_TEMPORAL_WIDE_BYTES, "byte count of one 64-word temporal chunk", "dec"),
    ("BLIT_TEMPORAL_TAIL_BYTES", BLIT_TEMPORAL_TAIL_BYTES, "byte count of the final temporal chunk", "dec"),
    ("BLIT_TEMPORAL_WIDE_MOD", HAM_DYNAMIC_PLANE_BYTES - BLIT_TEMPORAL_WIDE_BYTES, "next plane after wide chunk", "dec"),
    ("BLIT_TEMPORAL_TAIL_MOD", HAM_DYNAMIC_PLANE_BYTES - BLIT_TEMPORAL_TAIL_BYTES, "next plane after tail chunk", "dec"),
    ("BLIT_TEMPORAL_WIDE_MOD_LONG", ((HAM_DYNAMIC_PLANE_BYTES - BLIT_TEMPORAL_WIDE_BYTES) << 16) | (HAM_DYNAMIC_PLANE_BYTES - BLIT_TEMPORAL_WIDE_BYTES), "source and destination wide modulos", "hex8"),
    ("BLIT_TEMPORAL_TAIL_MOD_LONG", ((HAM_DYNAMIC_PLANE_BYTES - BLIT_TEMPORAL_TAIL_BYTES) << 16) | (HAM_DYNAMIC_PLANE_BYTES - BLIT_TEMPORAL_TAIL_BYTES), "source and destination tail modulos", "hex8"),
]


def fmt_c(value, kind):
    if kind == "hex2":
        return "0x%02X" % value
    if kind == "hex4":
        return "0x%04X" % value
    if kind == "hex8":
        return "0x%08X" % value
    return str(value)


def fmt_asm(value, kind):
    if kind == "hex2":
        return "$%02X" % value
    if kind == "hex4":
        return "$%04X" % value
    if kind == "hex8":
        return "$%08X" % value
    return str(value)


def write_c(path):
    with open(path, "w", newline="\n") as f:
        f.write("// Generated from Rotozoomer_shared_defs.py.\n")
        f.write("// Shared constants for Rotozoomer.c and Rotozoomer_vasm.s.\n\n")
        for name, value, comment, kind in DEFS:
            f.write("#define %-40s %s\n" % (name, fmt_c(value, kind)))


def write_asm(path):
    with open(path, "w", newline="\n") as f:
        f.write("; Generated from Rotozoomer_shared_defs.py.\n")
        f.write("; Shared constants for Rotozoomer.c and Rotozoomer_vasm.s.\n\n")
        for name, value, comment, kind in DEFS:
            f.write("%-40s equ\t%-10s ; %s\n" % (name, fmt_asm(value, kind), comment))


if __name__ == "__main__":
    BasePath = Path(__file__).resolve().parent
    write_c(BasePath / "Rotozoomer_shared.h")
    write_asm(BasePath / "Rotozoomer_shared.i")
