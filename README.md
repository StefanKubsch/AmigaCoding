# AmigaCoding

Coding for classic 68k Amigas in C99 and Assembler

I uploaded some examples for oldschool demo scene effects, written in C99 and Assembler (vasm), targeted at classic Amiga 500 OCS (PAL) and up.

Minimum requierements: Kickstart 1.3, 68000 CPU, 512KB Chip-RAM + 512KB Slow-RAM.

For better handling of reusable code, I am writing a framework called "lwmf" - lightweight media framework.

Performance-critical parts are done in assembly, like memory clearing, setting pixels etc.

For MOD Support I use the fantastic ptplayer (Protracker) library by Frank Wille (https://aminet.net/package/mus/play/ptplayer), that I included in my lwmf.

Used compiler:

vbcc 0.9h Patch 3

http://sun.hasenbraten.de/vbcc/

vbcc is still under development (last version is from 2022) and works pretty well and is simple to use. vbcc is available on nearly all platforms and perfect for cross-compiling. It also contains vasm and vlink for the assembler handling.

You´ll find a complete development environment for Windows under "Development".

Extract "vbcc.zip" to "C:\vbcc" (or whatever you want use) and set the Windows environment variable "VBCC" to the chosen path. Also, add "C:\vbcc" and "C:\vbcc\bin" to the PATH-Variable!
Copy "cygwin1.dll" from "Development" to "C:\Windows"

You´re done!

All you need to test your programs is an editor or IDE (I prefer Visual Studio Code, https://code.visualstudio.com/), an emulator like WinUAE (https://www.winuae.net/), with a set up Amiga OS installation. Or transfer your programs to a "real" Amiga via CF Card, Network etc.

I test my code on:

- a real Amiga 1200 with an iComp ACA1221 accelerator card and Amiga OS 3.1.4
- an emulated 14MHz A1200 in WinUAE (Kickstart 3.0, 2MB Chip-RAM)
- an emulated Amiga 500 in WinUAE (Kickstart 2.04, 512KB Chip-RAM + 512KB Slow-RAM)

Useful links:

68000 instructions overview - http://68k.hax.com/

Amiga registers documentation - http://amigadev.elowar.com/read/ADCD_2.1/Hardware_Manual_guide/node0060.html

