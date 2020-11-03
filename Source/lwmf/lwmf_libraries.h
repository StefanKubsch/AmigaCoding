#ifndef LWMF_LIBRARIRIES_H
#define LWMF_LIBRARIRIES_H

#include <exec/exec.h>
#include <exec/types.h>
#include <graphics/copper.h>
#include <graphics/rastport.h>
#include <datatypes/pictureclass.h>
#include <devices/timer.h>
#include <clib/timer_protos.h>  
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
void lwmf_ClearMemCPU(__reg("a0") long* Address, __reg("d0") long NumberOfBytes);
void lwmf_ClearMemCPU2(__reg("a0") long* Address, __reg("d7") long NumberOfBytes);
void lwmf_SetPixel(__reg("d1") WORD PosX, __reg("d2") WORD PosY,  __reg("d3") WORD Color,  __reg("a1") long* Target);

// Math

__reg("d0") ULONG lwmf_Random(void);

//
// External variables as defined in assembler sources
//

extern long GfxBase;
extern long IntuitionBase;
extern long DataTypesBase;


#endif /* LWMF_LIBRARIRIES_H */