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
    BOOL Paused;
};

static APTR lwmf_LoadMODFile(const STRPTR Filename, LONG *Size_Out)
{
    BPTR FileHandle = Open(Filename, MODE_OLDFILE);

    if (!FileHandle)
	{
        return NULL;
	}

    LONG LastPos = Seek(FileHandle, 0, OFFSET_END);

    if (LastPos == -1)
	{
        Close(FileHandle);
        return NULL;
    }

    LONG Size = Seek(FileHandle, 0, OFFSET_CURRENT);

	if (Size <= 0)
	{
        Close(FileHandle);
        return NULL;
    }

    if (Seek(FileHandle, 0, OFFSET_BEGINNING) == -1)
	{
        Close(FileHandle);
        return NULL;
    }

    APTR Buffer = AllocMem(Size, MEMF_CHIP);

    if (!Buffer)
	{
        Close(FileHandle);
        return NULL;
    }

    if (Read(FileHandle, Buffer, Size) != Size)
	{
        FreeMem(Buffer, Size);
        Close(FileHandle);
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
	mod->File = lwmf_LoadMODFile(Filename, &mod->Size);

	if (!mod->File)
	{
        PutStr("Could not load modfile.\n");
        return FALSE;
    }

	// Get VBR for ptplayer usage
	ULONG VBR = lwmf_GetVBR();

	// Install custom VBR handler for ptplayer (required for AGA compatibility and to avoid conflicts with OS handlers)
	mt_install(ptplayer_custom, (APTR)VBR, 1);

    // Init ptplayer with the loaded MOD file; no separate sample loading, ptplayer will handle it internally
	mt_init(ptplayer_custom, mod->File, NULL, 0);

	mod->Paused = FALSE;

	return TRUE;
}

void lwmf_StartMODPlayer(struct MODFile *mod)
{
	mt_Enable = 1;
	mod->Paused = FALSE;
}

void lwmf_PauseMODPlayer(struct MODFile *mod)
{
	mt_Enable = 0;
	mod->Paused = TRUE;
}

void lwmf_StopMODPlayer(struct MODFile *mod)
{
    mt_end(ptplayer_custom);
   	mt_Enable = 0;
	mod->Paused = FALSE;
}

void lwmf_CleanupModPlayer(struct MODFile *mod)
{
	mt_remove(ptplayer_custom);
    FreeMem(mod->File, mod->Size);
}


#endif /* LWMF_PTPLAYER_H */