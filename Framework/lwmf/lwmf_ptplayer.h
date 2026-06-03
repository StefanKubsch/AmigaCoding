#ifndef LWMF_PTPLAYER_H
#define LWMF_PTPLAYER_H

//
// ptplayer library by Frank Wille
// Aminet Source: https://aminet.net/package/mus/play/ptplayer
// Discussion on EAB: https://eab.abime.net/showthread.php?t=65430
//
// Implementation in lwmf by Stefan Kubsch/Deep4

// External functions from ptplayer module written in assembly

void mt_install(__reg("a6") void *custom, __reg("a0") void *VectorBase, __reg("d0") UBYTE PALflag);
void mt_remove(__reg("a6") void *custom);
void mt_init(__reg("a6") void *custom, __reg("a0") void *TrackerModule, __reg("a1") void *Samples, __reg("d0") UBYTE InitialSongPos);
void mt_end(__reg("a6") void *custom);

extern UBYTE mt_Enable;

// CUSTOM base address used for ptplayer under a separate name
static struct Custom *ptplayer_custom = (struct Custom *)0xDFF000;

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

	// Kickstart 1.3 compatible file size lookup: seek to EOF, then rewind.
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
	// Load MOD file into Chip RAM only. No hardware access, safe before TakeOverOS.
	if (!(mod->File = lwmf_LoadMODFile(Filename, &mod->Size)))
	{
		return FALSE;
	}

	return TRUE;
}

// Call this after lwmf_TakeOverOS() so mt_install sets up INTENA cleanly.
void lwmf_InstallModPlayer(struct MODFile *mod)
{
	// Get VBR for ptplayer usage.
	const ULONG VBR = lwmf_GetVBR();

	// Detect PAL CIA clock for ptplayer timing.
	const UBYTE PALFlag = SysBase->PowerSupplyFrequency < 59;

	// Install custom VBR handler for AGA compatibility and OS handler separation.
	mt_install(ptplayer_custom, (APTR)VBR, PALFlag);

	// Init ptplayer with the loaded MOD file. Samples are handled by ptplayer internally.
	mt_init(ptplayer_custom, mod->File, NULL, 0);
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
	mt_Enable = 0;
	mt_end(ptplayer_custom);
}

void lwmf_CleanupModPlayer(struct MODFile *mod)
{
	mt_Enable = 0;
	mt_end(ptplayer_custom);
	mt_remove(ptplayer_custom);

	if (mod->File)
	{
		FreeMem(mod->File, mod->Size);
		mod->File = NULL;
		mod->Size = 0;
	}
}


#endif // LWMF_PTPLAYER_H
