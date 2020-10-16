#ifndef LWMF_CLEANUP_H
#define LWMF_CLEANUP_H

void lwmf_CleanupAll(void);

void lwmf_CleanupAll(void)
{
	lwmf_ReleaseOS();
	lwmf_CleanupRastPort();
	lwmf_CleanupScreen();
	lwmf_CloseLibraries();
}


#endif /* LWMF_CLEANUP_H */