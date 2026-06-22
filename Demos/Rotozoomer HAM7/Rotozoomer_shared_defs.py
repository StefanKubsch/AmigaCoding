# Generates constants shared by the C and vasm parts of the Rotozoomer.

from pathlib import Path

HAM_COLUMNS = 56
HAM_ROWS = 52
HAM_PIXEL_SIZE = 4
HAM_FETCH_BYTES = (HAM_COLUMNS * HAM_PIXEL_SIZE) >> 3
HAM_FRAME_COUNT = 256
HAM_FRAME_PARAM_BYTES = 12
HAM_LIVE_ROWS = 2
HAM_TEMPORAL_START_ROW = 2
HAM_TEMPORAL_ROWS = 16
HAM_TEMPORAL_HALF_ROWS = HAM_TEMPORAL_ROWS // 2
HAM_TEMPORAL_LOWER_START_ROW = HAM_TEMPORAL_START_ROW + HAM_TEMPORAL_HALF_ROWS
HAM_HALFRATE_START_ROW = HAM_TEMPORAL_START_ROW + HAM_TEMPORAL_ROWS
HAM_DYNAMIC_ROWS = HAM_TEMPORAL_START_ROW + HAM_TEMPORAL_ROWS
HAM_HALFRATE_ROWS = HAM_ROWS - HAM_HALFRATE_START_ROW
HAM_ANGLE_PHASE_STEP = 1
HAM_DISPLAY_WIDTH = HAM_COLUMNS * HAM_PIXEL_SIZE
HAM_DISPLAY_HEIGHT = HAM_ROWS * HAM_PIXEL_SIZE
screen_width = 320
screen_height = 256
display_start_x = (screen_width - HAM_DISPLAY_WIDTH) // 2
pal_vpos_top = 0x2C
HAM_VPOS_START = pal_vpos_top + ((screen_height - HAM_DISPLAY_HEIGHT) // 2)
display_stop_vpos = HAM_VPOS_START + HAM_DISPLAY_HEIGHT
ddf_shift_bytes = display_start_x >> 3

HAM_DYNAMIC_PLANE_BYTES = HAM_FETCH_BYTES * HAM_DYNAMIC_ROWS
HAM_DYNAMIC_BITMAP_BYTES = HAM_DYNAMIC_PLANE_BYTES * 4
HAM_HALFRATE_ROW_CACHE_PLANE_BYTES = HAM_FETCH_BYTES * HAM_HALFRATE_ROWS
HAM_HALFRATE_ROW_CACHE_FRAME_BYTES = HAM_HALFRATE_ROW_CACHE_PLANE_BYTES * 4
HAM_HALFRATE_ROW_CACHE_BYTES = HAM_HALFRATE_ROW_CACHE_FRAME_BYTES * (HAM_FRAME_COUNT // 2)
HAM_TEMPORAL_UPPER_DEST_OFFSET = HAM_TEMPORAL_START_ROW * HAM_FETCH_BYTES
HAM_TEMPORAL_LOWER_DEST_OFFSET = HAM_TEMPORAL_LOWER_START_ROW * HAM_FETCH_BYTES
HAM_AGA_CONTROL_PLANE_BYTES = HAM_FETCH_BYTES * HAM_ROWS
HAM_AGA_CONTROL_PLANES_BYTES = HAM_AGA_CONTROL_PLANE_BYTES * 2

HAM_AGA_BPLCON3_RESET = 0x0000
HAM_AGA_BPLCON4_RESET = 0x0000
HAM_AGA_FMODE_RESET = 0x0000
HAM_AGA_BPLCON3_LOCT = 0x0200
HAM_AGA_DISPLAY_BPU = 6


def copper_layout(slot_words, aga_prefix_words):
    index = 0
    wrapped = False
    split_rows = {
        HAM_TEMPORAL_START_ROW: "temporal_upper",
        HAM_TEMPORAL_LOWER_START_ROW: "temporal_lower",
        HAM_HALFRATE_START_ROW: "halfrate",
    }
    slots = {}

    def append_wait(vpos):
        nonlocal index, wrapped
        if (vpos > 0x00FF) and not wrapped:
            index += 2
            wrapped = True
        index += 2

    def append_modulo():
        nonlocal index
        index += 4

    def append_bplptr_slots(name):
        nonlocal index
        slots[name] = index + 1
        index += slot_words

    index += 8                         # DIW/DDF registers
    index += aga_prefix_words          # optional AGA compatibility registers
    index += 10                        # BPLCON and modulo registers
    index += 4                         # BPL5DAT/BPL6DAT control words for OCS quirk / harmless on AGA

    append_bplptr_slots("initial")

    for row in range(HAM_ROWS - 1):
        next_row = row + 1

        if next_row in split_rows:
            append_wait(HAM_VPOS_START + (next_row * HAM_PIXEL_SIZE))
            append_bplptr_slots(split_rows[next_row])
        else:
            append_wait(HAM_VPOS_START + (row * HAM_PIXEL_SIZE) + (HAM_PIXEL_SIZE - 1))
            append_modulo()
            append_wait(HAM_VPOS_START + (next_row * HAM_PIXEL_SIZE))
            append_modulo()

    index += 2                         # copper end marker
    return slots, index


OCS_COPPER_SLOTS, HAM_OCS_COPPER_WORDS = copper_layout(16, 0)
AGA_COPPER_SLOTS, HAM_AGA_COPPER_WORDS = copper_layout(24, 6)

HAM_OCS_COPPER_BPLPTR_WORD = OCS_COPPER_SLOTS["initial"]
HAM_OCS_COPPER_TEMPORAL_UPPER_BPLPTR_WORD = OCS_COPPER_SLOTS["temporal_upper"]
HAM_OCS_COPPER_TEMPORAL_LOWER_BPLPTR_WORD = OCS_COPPER_SLOTS["temporal_lower"]
HAM_OCS_COPPER_HALFRATE_BPLPTR_WORD = OCS_COPPER_SLOTS["halfrate"]
HAM_AGA_COPPER_BPLPTR_WORD = AGA_COPPER_SLOTS["initial"]
HAM_AGA_COPPER_TEMPORAL_UPPER_BPLPTR_WORD = AGA_COPPER_SLOTS["temporal_upper"]
HAM_AGA_COPPER_TEMPORAL_LOWER_BPLPTR_WORD = AGA_COPPER_SLOTS["temporal_lower"]
HAM_AGA_COPPER_HALFRATE_BPLPTR_WORD = AGA_COPPER_SLOTS["halfrate"]

HAM_OCS_COPPER_BYTES = HAM_OCS_COPPER_WORDS * 2
HAM_AGA_COPPER_BYTES = HAM_AGA_COPPER_WORDS * 2
HAM_COPPER_WORDS = max(HAM_OCS_COPPER_WORDS, HAM_AGA_COPPER_WORDS)
HAM_COPPER_BYTES = HAM_COPPER_WORDS * 2
HAM_CHIP_BLOCK_BYTES = (HAM_DYNAMIC_BITMAP_BYTES * 2) + (HAM_COPPER_BYTES * 2)

DEFS = [
    ("HAM_COLUMNS", HAM_COLUMNS, "number of HAM cells per row", "dec"),
    ("HAM_ROWS", HAM_ROWS, "number of displayed HAM cell rows", "dec"),
    ("HAM_PIXEL_SIZE", HAM_PIXEL_SIZE, "cell size in display pixels", "dec"),
    ("HAM_DISPLAY_WIDTH", HAM_DISPLAY_WIDTH, "visible HAM width in pixels", "dec"),
    ("HAM_DISPLAY_HEIGHT", HAM_DISPLAY_HEIGHT, "visible HAM height in pixels", "dec"),
    ("HAM_FETCH_BYTES", HAM_FETCH_BYTES, "bytes per rendered bitplane row", "dec"),
    ("HAM_FRAME_COUNT", HAM_FRAME_COUNT, "number of animation frames", "dec"),
    ("HAM_FRAME_PARAM_BYTES", HAM_FRAME_PARAM_BYTES, "bytes per frame-parameter entry", "dec"),
    ("HAM_LIVE_ROWS", HAM_LIVE_ROWS, "number of runtime-rendered core cell rows", "dec"),
    ("HAM_TEMPORAL_START_ROW", HAM_TEMPORAL_START_ROW, "first temporal dynamic row", "dec"),
    ("HAM_TEMPORAL_ROWS", HAM_TEMPORAL_ROWS, "number of temporal dynamic rows", "dec"),
    ("HAM_TEMPORAL_HALF_ROWS", HAM_TEMPORAL_HALF_ROWS, "number of rows in one temporal half", "dec"),
    ("HAM_TEMPORAL_LOWER_START_ROW", HAM_TEMPORAL_LOWER_START_ROW, "first row of the lower temporal half", "dec"),
    ("HAM_HALFRATE_START_ROW", HAM_HALFRATE_START_ROW, "first half-rate cached row", "dec"),
    ("HAM_DYNAMIC_ROWS", HAM_DYNAMIC_ROWS, "compact live and temporal rows per frame", "dec"),
    ("HAM_DYNAMIC_PLANE_BYTES", HAM_DYNAMIC_PLANE_BYTES, "bytes per compact dynamic bitplane", "dec"),
    ("HAM_DYNAMIC_BITMAP_BYTES", HAM_DYNAMIC_BITMAP_BYTES, "bytes per compact dynamic bitmap", "dec"),
    ("HAM_HALFRATE_ROWS", HAM_HALFRATE_ROWS, "number of half-rate rows per cached frame", "dec"),
    ("HAM_HALFRATE_ROW_CACHE_PLANE_BYTES", HAM_HALFRATE_ROW_CACHE_PLANE_BYTES, "bytes per half-rate cache bitplane", "dec"),
    ("HAM_HALFRATE_ROW_CACHE_FRAME_BYTES", HAM_HALFRATE_ROW_CACHE_FRAME_BYTES, "bytes per half-rate cache frame", "dec"),
    ("HAM_HALFRATE_ROW_CACHE_BYTES", HAM_HALFRATE_ROW_CACHE_BYTES, "bytes for all half-rate cache frames", "dec"),
    ("HAM_TEMPORAL_UPPER_DEST_OFFSET", HAM_TEMPORAL_UPPER_DEST_OFFSET, "compact row 2 byte offset in dynamic planes", "dec"),
    ("HAM_TEMPORAL_LOWER_DEST_OFFSET", HAM_TEMPORAL_LOWER_DEST_OFFSET, "compact lower temporal-half byte offset in dynamic planes", "dec"),
    ("HAM_AGA_CONTROL_PLANE_BYTES", HAM_AGA_CONTROL_PLANE_BYTES, "bytes per AGA fixed HAM-control plane", "dec"),
    ("HAM_AGA_CONTROL_PLANES_BYTES", HAM_AGA_CONTROL_PLANES_BYTES, "bytes for both AGA fixed HAM-control planes", "dec"),
    ("HAM_AGA_BPLCON3_RESET", HAM_AGA_BPLCON3_RESET, "AGA BPLCON3 palette-bank and LOCT reset", "hex4"),
    ("HAM_AGA_BPLCON4_RESET", HAM_AGA_BPLCON4_RESET, "AGA BPLCON4 bitplane XOR reset", "hex4"),
    ("HAM_AGA_FMODE_RESET", HAM_AGA_FMODE_RESET, "AGA 16-bit compatible fetch mode", "hex4"),
    ("HAM_AGA_BPLCON3_LOCT", HAM_AGA_BPLCON3_LOCT, "AGA low-order color-table write select", "hex4"),
    ("HAM_AGA_DISPLAY_BPU", HAM_AGA_DISPLAY_BPU, "AGA normal HAM6 bitplane count", "dec"),
    ("HAM_OCS_COPPER_BPLPTR_WORD", HAM_OCS_COPPER_BPLPTR_WORD, "OCS value slot for initial dynamic row pointers", "dec"),
    ("HAM_OCS_COPPER_TEMPORAL_UPPER_BPLPTR_WORD", HAM_OCS_COPPER_TEMPORAL_UPPER_BPLPTR_WORD, "OCS value slot for upper temporal row pointers", "dec"),
    ("HAM_OCS_COPPER_TEMPORAL_UPPER_BPLPTR_BYTES", HAM_OCS_COPPER_TEMPORAL_UPPER_BPLPTR_WORD * 2, "OCS byte slot for upper temporal row pointers", "dec"),
    ("HAM_OCS_COPPER_TEMPORAL_LOWER_BPLPTR_WORD", HAM_OCS_COPPER_TEMPORAL_LOWER_BPLPTR_WORD, "OCS value slot for lower temporal row pointers", "dec"),
    ("HAM_OCS_COPPER_TEMPORAL_LOWER_BPLPTR_BYTES", HAM_OCS_COPPER_TEMPORAL_LOWER_BPLPTR_WORD * 2, "OCS byte slot for lower temporal row pointers", "dec"),
    ("HAM_OCS_COPPER_HALFRATE_BPLPTR_WORD", HAM_OCS_COPPER_HALFRATE_BPLPTR_WORD, "OCS value slot for half-rate row pointers", "dec"),
    ("HAM_OCS_COPPER_HALFRATE_BPLPTR_BYTES", HAM_OCS_COPPER_HALFRATE_BPLPTR_WORD * 2, "OCS byte slot for half-rate row pointers", "dec"),
    ("HAM_OCS_COPPER_WORDS", HAM_OCS_COPPER_WORDS, "OCS copper list words", "dec"),
    ("HAM_OCS_COPPER_BYTES", HAM_OCS_COPPER_BYTES, "OCS copper list bytes", "dec"),
    ("HAM_AGA_COPPER_BPLPTR_WORD", HAM_AGA_COPPER_BPLPTR_WORD, "AGA value slot for initial dynamic row pointers", "dec"),
    ("HAM_AGA_COPPER_TEMPORAL_UPPER_BPLPTR_WORD", HAM_AGA_COPPER_TEMPORAL_UPPER_BPLPTR_WORD, "AGA value slot for upper temporal row pointers", "dec"),
    ("HAM_AGA_COPPER_TEMPORAL_UPPER_BPLPTR_BYTES", HAM_AGA_COPPER_TEMPORAL_UPPER_BPLPTR_WORD * 2, "AGA byte slot for upper temporal row pointers", "dec"),
    ("HAM_AGA_COPPER_TEMPORAL_LOWER_BPLPTR_WORD", HAM_AGA_COPPER_TEMPORAL_LOWER_BPLPTR_WORD, "AGA value slot for lower temporal row pointers", "dec"),
    ("HAM_AGA_COPPER_TEMPORAL_LOWER_BPLPTR_BYTES", HAM_AGA_COPPER_TEMPORAL_LOWER_BPLPTR_WORD * 2, "AGA byte slot for lower temporal row pointers", "dec"),
    ("HAM_AGA_COPPER_HALFRATE_BPLPTR_WORD", HAM_AGA_COPPER_HALFRATE_BPLPTR_WORD, "AGA value slot for half-rate row pointers", "dec"),
    ("HAM_AGA_COPPER_HALFRATE_BPLPTR_BYTES", HAM_AGA_COPPER_HALFRATE_BPLPTR_WORD * 2, "AGA byte slot for half-rate row pointers", "dec"),
    ("HAM_AGA_COPPER_WORDS", HAM_AGA_COPPER_WORDS, "AGA copper list words", "dec"),
    ("HAM_AGA_COPPER_BYTES", HAM_AGA_COPPER_BYTES, "AGA copper list bytes", "dec"),
    ("HAM_COPPER_WORDS", HAM_COPPER_WORDS, "maximum copper list words per buffer", "dec"),
    ("HAM_COPPER_BYTES", HAM_COPPER_BYTES, "maximum copper list bytes per buffer", "dec"),
    ("HAM_CHIP_BLOCK_BYTES", HAM_CHIP_BLOCK_BYTES, "dynamic buffers plus double copper list block bytes", "dec"),
    ("HAM_HALF_COLUMNS", HAM_COLUMNS // 2, "half of the HAM cell columns", "dec"),
    ("HAM_HALF_ROWS", HAM_ROWS // 2, "half of the HAM cell rows", "dec"),
    ("HAM_VPOS_START", HAM_VPOS_START, "first visible HAM display line", "hex4"),
    ("HAM_DIWSTRT", ((HAM_VPOS_START & 0xFF) << 8) | 0x0081, "display window start register value", "hex4"),
    ("HAM_DIWSTOP", ((display_stop_vpos & 0xFF) << 8) | 0x00C1, "display window stop register value", "hex4"),
    ("HAM_DDFSTRT", 0x0038 + (ddf_shift_bytes * 4), "data fetch start register value", "hex4"),
    ("HAM_DDFSTOP", 0x00D0 - (ddf_shift_bytes * 4), "data fetch stop register value", "hex4"),
    ("HAM_REPEAT_MOD", (-HAM_FETCH_BYTES) & 0xFFFF, "modulo for repeating a 4-line cell row", "hex4"),
    ("HAM_ADVANCE_MOD", 0, "modulo for advancing to the next cell row", "dec"),
    ("HAM_DISPLAY_BPU", 7, "OCS BPLDAT-quirk bitplane count", "dec"),
    ("HAM_CONTROL_WORD_P5", 0x3333, "BPL5DAT/HAM control plane 5 pattern", "hex4"),
    ("HAM_CONTROL_WORD_P6", 0x6666, "BPL6DAT/HAM control plane 6 pattern", "hex4"),
    ("HAM_CORE_DONE_LOW", (HAM_VPOS_START + (HAM_LIVE_ROWS * HAM_PIXEL_SIZE)) & 0xFF, "low byte after dynamic rows 0-1 are off-screen", "hex2"),
    ("HAM_TEMPORAL_UPPER_DONE_LOW", (HAM_VPOS_START + ((HAM_TEMPORAL_START_ROW + HAM_TEMPORAL_HALF_ROWS) * HAM_PIXEL_SIZE)) & 0xFF, "low byte after upper temporal rows are off-screen", "hex2"),
    ("HAM_TEMPORAL_DONE_LOW", (HAM_VPOS_START + ((HAM_TEMPORAL_START_ROW + HAM_TEMPORAL_ROWS) * HAM_PIXEL_SIZE)) & 0xFF, "low byte after temporal rows are off-screen", "hex2"),
    ("HAM_ZOOM_BASE", 256, "base zoom factor", "dec"),
    ("HAM_ZOOM_AMPLITUDE", 96, "zoom sine amplitude", "dec"),
    ("HAM_ANGLE_PHASE_STEP", HAM_ANGLE_PHASE_STEP, "phase step per frame", "dec"),
    ("HAM_CENTER_U", 0x4000, "texture center U", "hex4"),
    ("HAM_CENTER_V", 0x4000, "texture center V", "hex4"),
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
            f.write("#define %-48s %s\n" % (name, fmt_c(value, kind)))


def write_asm(path):
    with open(path, "w", newline="\n") as f:
        f.write("; Generated from Rotozoomer_shared_defs.py.\n")
        f.write("; Shared constants for Rotozoomer.c and Rotozoomer_vasm.s.\n\n")
        for name, value, comment, kind in DEFS:
            f.write("%-48s equ\t%-10s ; %s\n" % (name, fmt_asm(value, kind), comment))


if __name__ == "__main__":
    BasePath = Path(__file__).resolve().parent
    write_c(BasePath / "Rotozoomer_shared.h")
    write_asm(BasePath / "Rotozoomer_shared.i")
