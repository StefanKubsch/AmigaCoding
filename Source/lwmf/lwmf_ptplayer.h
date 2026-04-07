#ifndef LWMF_PTPLAYER_H
#define LWMF_PTPLAYER_H

//
// ptplayer library by Frank Wille
// Aminet Source: https://aminet.net/package/mus/play/ptplayer
// Discussion on EAB: https://eab.abime.net/showthread.php?t=65430
//
// Implementation in lwmf by Stefan Kubsch/Deep4

// External funtions from ptplayer module (written in assembly)

void mt_install(__reg("a6") void *custom,__reg("a0") void *VectorBase, __reg("d0") UBYTE PALflag);
void mt_remove(__reg("a6") void *custom);
void mt_init(__reg("a6") void *custom,	__reg("a0") void *TrackerModule, __reg("a1") void *Samples, __reg("d0") UBYTE InitialSongPos);
void mt_end(__reg("a6") void *custom);

extern UBYTE mt_Enable;

// CUSTOM base adress used for ptplayer; it´s a redefine wth a different name
struct Custom *ptplayer_custom = (struct Custom *)0xDFF000;

struct MODFile
{
	APTR File;
	LONG Size;
};

static APTR lwmf_LoadMODFile(const STRPTR Filename, LONG *Size_Out)
{
    BPTR FileHandle = Open(Filename, MODE_OLDFILE);

    if (!FileHandle)
    {
        return NULL;
    }

    // KS 1.3-kompatible Dateigroesse: ans Ende seekern, Position auslesen
    if (Seek(FileHandle, 0, OFFSET_END) < 0)
    {
        Close(FileHandle);
        return NULL;
    }

    const LONG Size = Seek(FileHandle, 0, OFFSET_BEGINNING);

    if (Size <= 0)
    {
        Close(FileHandle);
        return NULL;
    }

    APTR Buffer = AllocMem(Size, MEMF_CHIP | MEMF_CLEAR);

    if (!Buffer)
    {
        Close(FileHandle);
        return NULL;
    }

    if (Read(FileHandle, Buffer, Size) != Size)
    {
        Close(FileHandle);
        FreeMem(Buffer, Size);
        return NULL;
    }

    Close(FileHandle);

    if (Size_Out)
    {
        *Size_Out = Size;
    }

    return Buffer;
}

BOOL lwmf_InitModPlayer(struct MODFile *mod, const STRPTR Filename)
{
	// Load MOD file into memory
	if (!(mod->File = lwmf_LoadMODFile(Filename, &mod->Size)))
	{
        PutStr("Could not load modfile.\n");
        return FALSE;
    }

	// Get VBR for ptplayer usage
	const ULONG VBR = lwmf_GetVBR();

    // CIA clock is PAL or NTSC?
    const UBYTE PALFlag = SysBase->PowerSupplyFrequency < 59;

	// Install custom VBR handler for ptplayer (required for AGA compatibility and to avoid conflicts with OS handlers)
	mt_install(ptplayer_custom, (APTR)VBR, PALFlag);

    // Init ptplayer with the loaded MOD file; no separate sample loading, ptplayer will handle it internally
	mt_init(ptplayer_custom, mod->File, NULL, 0);

	return TRUE;
}

void lwmf_StartMODPlayer(struct MODFile *mod)
{
	mt_Enable = 1;
}

void lwmf_PauseMODPlayer(struct MODFile *mod)
{
	mt_Enable = 0;
}

void lwmf_StopMODPlayer(struct MODFile *mod)
{
    mt_end(ptplayer_custom);
}

void lwmf_CleanupModPlayer(struct MODFile *mod)
{
    if (mod->File)
	{
        FreeMem(mod->File, mod->Size);
        mod->File = NULL;
	}

   	mt_remove(ptplayer_custom);
}


#endif /* LWMF_PTPLAYER_H */