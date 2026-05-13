import math

# Generate 256-entry sine table (range 0..63, centered at 32)

SIZE = 256
AMPLITUDE = 31
OFFSET = 32

def generate_table():
    table = []
    for i in range(SIZE):
        angle = (i / SIZE) * 2.0 * math.pi
        # rounding tuned to closely match classic tables
        value = int(OFFSET + math.sin(angle) * AMPLITUDE + 0.5)
        table.append(value)
    return table

def print_c_table(table):
    print("const UBYTE SinTab256[256] =")
    print("{")

    for i in range(0, SIZE, 32):
        line = ", ".join(f"{v:2d}" for v in table[i:i+32])
        if i + 32 < SIZE:
            print(f"    {line},")
        else:
            print(f"    {line}")

    print("};")

if __name__ == "__main__":
    tab = generate_table()
    print_c_table(tab)
