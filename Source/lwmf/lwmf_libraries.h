#ifndef LWMF_LIBRARIRIES_H
#define LWMF_LIBRARIRIES_H

#include <exec/exec.h>
#include <exec/types.h>
#include <graphics/copper.h>
#include <graphics/rastport.h>
#include <datatypes/pictureclass.h>
#include <clib/exec_protos.h>
#include <clib/dos_protos.h>
#include <clib/graphics_protos.h>
#include <clib/alib_protos.h>
#include <clib/datatypes_protos.h>

//
// Global symbols for our assembler functions
//

// Hardware

__reg("d0") ULONG lwmf_LoadLibraries(void);
void lwmf_CloseLibraries();
void lwmf_TakeOverOS(void);
void lwmf_ReleaseOS(void);
void lwmf_WaitVertBlank(void);
void lwmf_WaitBlitter(void);
void lwmf_ClearMemCPU(__reg("a1") long* StartAddress, __reg("d7") long NumberOfBytes);
void lwmf_ClearScreen(__reg("a1") long* StartAddress);
void lwmf_SetPixel(__reg("d0") WORD PosX, __reg("d1") WORD PosY,  __reg("d2") UBYTE Color,  __reg("a0") long* Target);
void lwmf_BlitTile(__reg("a1") long* Src, __reg("d0") WORD Modulo, __reg("a2") long* Dst, __reg("d1") long DstOffset, __reg("d2") WORD Size);

// Math

__reg("d0") ULONG lwmf_Random(void);

//
// External variables as defined in assembler sources
//

extern long GfxBase;
extern long IntuitionBase;
extern long DataTypesBase;


#endif /* LWMF_LIBRARIRIES_H */