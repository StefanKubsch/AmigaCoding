# AmigaCoding
 
Coding for classic 68k Amigas in C99.

I uploaded some examples for oldschool demo scene effects, written in C99, which should run on all classic Amigas (A500, A600, A1200 etc).

Requierements: Amiga OS 3.0 and Kickstart 3.0.

For better handling of reusable code, I am writing a framework called "lwmf" - lightweight media framework.

Used compiler:

vbcc 0.9g

http://sun.hasenbraten.de/vbcc/

vbcc is still under development (last version is from 2019) and works pretty well and is simple to use. vbcc is available on nearly all platforms and perfect for cross-compiling.

You´ll find a complete development environment for Windows under "Development".

Extract "vbcc.zip" to "C:\vbcc" (or whatever you want use) and set the Windows environment variable "VBCC" to the chosen path.
Copy "cygwin1.dll" from "Development" to "C:\Windows"

You´re done!

All you need to test your programs is an editor (I prefer Visual Studio Code, https://code.visualstudio.com/) emulator like WinUAE (https://www.winuae.net/), with a set up Amiga OS installation. Or transfer you programs to a "real" Amiga via CF Card, Network etc.

I test my code on:

- a real Amiga 1200 with an iComp ACA1221 accelerator card and Amiga OS 3.1.4
- a "stock" 14MHz A1200 in WinUA and Amiga OS 3.1.4
- a "stock" Amiga 500 in WinUAE and Amiga OS 3.1