#ifndef LWMF_PTPLAYER_H
#define LWMF_PTPLAYER_H

// External funtions from ptplayer module (written in assembly)

void mt_install(__reg("a6") void *custom,__reg("a0") void *VectorBase, __reg("d0") UBYTE PALflag);
void mt_remove(__reg("a6") void *custom);
void mt_init(__reg("a6") void *custom,	__reg("a0") void *TrackerModule, __reg("a1") void *Samples, __reg("d0") UBYTE InitialSongPos);
void mt_end(__reg("a6") void *custom);
extern UBYTE mt_Enable;


static APTR lwmf_LoadMODFile(const STRPTR Filename, LONG *Size_Out)
{
    BPTR FileHandle = Open(Filename, MODE_OLDFILE);

    if (!FileHandle)
	{
        return NULL;
	}

    LONG oldpos = Seek(FileHandle, 0, OFFSET_END);

    if (oldpos == -1)
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


#endif /* LWMF_PTPLAYER_H */