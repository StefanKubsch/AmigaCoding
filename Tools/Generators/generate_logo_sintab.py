LOGO_STEPS = 256
LOGO_INDEX_STEP = 3

LogoSinTabSrcX = [
    64,70,76,82,87,93,98,103,107,111,114,117,120,122,123,124,
    124,123,122,121,119,116,113,109,105,100,95,90,84,78,72,66,
    60,55,49,43,37,32,27,23,19,15,12,9,7,5,4,4,
    4,5,6,8,11,14,18,22,26,31,36,42,47,53,59,65
]

LogoSinTabSrcY = [
    19,23,26,29,32,34,36,37,37,37,35,34,31,28,25,22,
    18,14,11,8,5,3,2,1,1,2,3,5,8,11,14,18,
    21,25,28,31,33,35,36,37,37,36,34,32,30,26,23,19,
    16,12,9,6,4,2,1,1,1,2,4,7,9,13,16,20
]


def c_div(num, den):
    if num < 0:
        return -((-num) // den)
    return num // den


def build_logo_tables():
    cumulative = [0]
    total_length = 0

    for i in range(64):
        nxt = (i + 1) & 63
        dx = LogoSinTabSrcX[nxt] - LogoSinTabSrcX[i]
        dy = LogoSinTabSrcY[nxt] - LogoSinTabSrcY[i]
        seg_len = abs(dx) + abs(dy)

        total_length += seg_len if seg_len else 1
        cumulative.append(total_length)

    tab_x = []
    tab_y = []
    segment = 0

    for i in range(LOGO_STEPS):
        target = (i * total_length) // LOGO_STEPS

        while segment < 63 and cumulative[segment + 1] <= target:
            segment += 1

        nxt = (segment + 1) & 63
        seg_start = cumulative[segment]
        seg_len = cumulative[segment + 1] - seg_start
        dx = LogoSinTabSrcX[nxt] - LogoSinTabSrcX[segment]
        dy = LogoSinTabSrcY[nxt] - LogoSinTabSrcY[segment]
        frac = target - seg_start

        if seg_len:
            tab_x.append(LogoSinTabSrcX[segment] + c_div(dx * frac + (seg_len >> 1), seg_len))
            tab_y.append(LogoSinTabSrcY[segment] + c_div(dy * frac + (seg_len >> 1), seg_len))
        else:
            tab_x.append(LogoSinTabSrcX[segment])
            tab_y.append(LogoSinTabSrcY[segment])

    return tab_x, tab_y


def print_c_table(name, values):
    print(f"static const UBYTE {name}[LOGO_STEPS] =")
    print("{")
    for i in range(0, len(values), 16):
        chunk = values[i:i + 16]
        line = "\t" + ",".join(f"{v:3d}" for v in chunk)
        if i + 16 < len(values):
            line += ","
        print(line)
    print("};")


if __name__ == "__main__":
    tab_x, tab_y = build_logo_tables()

    print(f"#define LOGO_STEPS            {LOGO_STEPS}")
    print(f"#define LOGO_INDEX_STEP       {LOGO_INDEX_STEP}")
    print()
    print_c_table("LogoSinTabX", tab_x)
    print()
    print_c_table("LogoSinTabY", tab_y)
