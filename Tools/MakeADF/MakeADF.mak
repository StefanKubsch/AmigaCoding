# Run with:
# make -f MakeADF.mak adf
#

ADF=demo.adf
PROG=A1200_Intro
GFXDIR=gfx
SFXDIR=sfx

adf: $(PROG)
	echo $(PROG) > startup-sequence
	xdftool $(ADF) format DemoDisk
	xdftool $(ADF) boot install
	xdftool $(ADF) makedir S
	xdftool $(ADF) write $(PROG) $(PROG)
	xdftool $(ADF) write $(GFXDIR) $(GFXDIR)
	xdftool $(ADF) write $(SFXDIR) $(SFXDIR)
	xdftool $(ADF) write startup-sequence S/startup-sequence
	xdftool $(ADF) list
	del /Q startup-sequence 2>NUL