# AmigaCoding

Coding for classic 68k Amigas in C99 and Assembler

I uploaded some examples for oldschool demo scene effects, written in C99 and Assembler (vasm), targeted at classic Amiga 500 OCS (PAL) and up.

Minimum requierements: Kickstart 1.3, 68000 CPU, 512KB Chip-RAM + 512KB Slow-RAM.

---

Included examples, coded for speed and memory, so there are no guards etc:

- Copper-Chunky Rotozoomer 4 bitplanes (Affine rotation)
- Copper-Chunky Rotozoomer 4 bitplanes with sprite assist
- Copper-Chunky Rotozoomer 5 bitplanes (Affine rotation)
- Copper Plasma
- Morphing dots
- Shadebobs
- Sinescroller
- Vectorballs

A demo with proper errorhandling and full use of the framework is also included:

- Amiga 1200 intro

---

For better handling of reusable code, I am writing a framework called "lwmf" - lightweight media framework.

Performance-critical parts are done in assembly, like memory clearing, setting pixels etc.

Currently implemented:

OS / Hardware

    long lwmf_GetVBR(void);
    UWORD lwmf_LoadGraphicsLib(void);
    void lwmf_CloseLibraries();
    void lwmf_TakeOverOS(void);
    void lwmf_ReleaseOS(void);
    void lwmf_OwnBlitter(void);
    void lwmf_DisownBlitter(void);
    void lwmf_WaitVertBlank(void);
    void lwmf_WaitBlitter(void);
    void lwmf_ClearMemCPU(__reg("a1") long* StartAddress, __reg("d7") long NumberOfBytes);
    void lwmf_ClearScreen(__reg("a0") long* StartAddress);
    void lwmf_BlitClearLines(__reg("d0") UWORD StartLine, __reg("d1") UWORD NumberOfLines, __reg("a0") long* Target);
    void lwmf_SetPixel(__reg("d0") WORD PosX, __reg("d1") WORD PosY,  __reg("d2") UBYTE Color,  __reg("a0") long* Target);
    void lwmf_SetPixel1bpl(__reg("d0") WORD PosX, __reg("d1") WORD PosY, __reg("a0") long* Target);

Screen / Bitmaps / Doublebuffer

    static BOOL lwmf_InitScreenBitmaps(void);
    static void lwmf_CleanupScreenBitmaps(void);

Images

    struct lwmf_Image* lwmf_LoadImage(const char* Filename);
    void lwmf_DeleteImage(struct lwmf_Image* Image);

Math

    ULONG lwmf_Random(void);
    static UWORD lwmf_RGBLerp(UWORD c0, UWORD c1, UWORD t, UWORD tmax);

Memoryhandling

    static APTR lwmf_AllocCpuMem(ULONG Size, ULONG Flags);

Text

    void lwmf_Text(const char* Text, UWORD PosX, const UWORD PosY, const UBYTE Color, long* Target);

MOD Support / ptplayer

    static APTR lwmf_LoadMODFile(const STRPTR Filename, LONG *Size_Out);
    BOOL lwmf_InitModPlayer(struct MODFile *mod, const STRPTR Filename);
    void lwmf_InstallModPlayer(struct MODFile *mod);
    void lwmf_StartMODPlayer(struct MODFile *mod);
    void lwmf_PauseMODPlayer(struct MODFile *mod);
    void lwmf_StopMODPlayer(struct MODFile *mod);
    void lwmf_CleanupModPlayer(struct MODFile *mod);

    For MOD Support I use the fantastic ptplayer (Protracker) library by Frank Wille (https://aminet.net/package/mus/play/ptplayer).

---

Used compiler:

vbcc 0.9h Patch 3

http://sun.hasenbraten.de/vbcc/

vbcc is still under development (last version is from 2022) and works pretty well and is simple to use. vbcc is available on nearly all platforms and perfect for cross-compiling. It also contains vasm and vlink for the assembler handling.

You´ll find a complete development environment for Windows under "Development".

Extract "vbcc.zip" to "C:\vbcc" (or whatever you want use) and set the Windows environment variable "VBCC" to the chosen path. Also, add "C:\vbcc" and "C:\vbcc\bin" to the PATH-Variable!
Copy "cygwin1.dll" from "Development" to "C:\Windows"

You´re done!

All you need to test your programs is an editor or IDE (I prefer Visual Studio Code, https://code.visualstudio.com/), an emulator like WinUAE (https://www.winuae.net/), with a set up Amiga OS installation. Or transfer your programs to a "real" Amiga via CF Card, Network etc.

---

I test my code on:

- a real Amiga 1200 with an iComp ACA1221 accelerator card and Amiga OS 3.1.4
- an emulated 14MHz A1200 in WinUAE (Kickstart 3.0, 2MB Chip-RAM)
- an emulated Amiga 500 in WinUAE (Kickstart 2.04, 512KB Chip-RAM + 512KB Slow-RAM)

---

Useful links:

68000 instructions overview - http://68k.hax.com/

Amiga registers documentation - http://amigadev.elowar.com/read/ADCD_2.1/Hardware_Manual_guide/node0060.html

