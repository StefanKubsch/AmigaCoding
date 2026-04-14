#ifndef LWMF_LIBRARIES_H
#define LWMF_LIBRARIES_H

#include <exec/exec.h>
#include <clib/exec_protos.h>
#include <graphics/gfx.h>
#include <proto/dos.h>

//
// Global symbols for our assembler functions
//

// Hardware

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
void lwmf_BlitTile(__reg("a0") long* SrcAddr, __reg("d0") WORD SrcX, __reg("d1") WORD SrcY, __reg("a1") long* DstAddr, __reg("d2") WORD PosX, __reg("d3") WORD PosY, __reg("d4") WORD Width, __reg("d5") WORD Height, __reg("d6") WORD SrcWidth);

//
// External variables as defined in assembler sources
//

extern long GfxBase;

#endif /* LWMF_LIBRARIES_H */