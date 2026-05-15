# Run with:
# make -f MakeADF.mak adf
#

ADF=demo.adf
PROG=RotoZoomer
GFXDIR=gfx

$(PROG): Rotozoomer.c Rotozoomer_vasm.s Rotozoomer_shared_defs.py
	python Rotozoomer_shared_defs.py
	vasmm68k_mot -Fhunk -showopt -o ".\lwmf\include\lwmf_hardware_vasm.o" ".\lwmf\lwmf_hardware_vasm.s"
	vasmm68k_mot -Fcdef -o ".\lwmf\lwmf_Defines.h" ".\lwmf\lwmf_hardware_vasm.s"
	vasmm68k_mot -Fhunk -showopt -o "Rotozoomer_vasm.o" "Rotozoomer_vasm.s"
	vc -O4 -speed -final -sd -sc -cpu=68000 Rotozoomer.c "Rotozoomer_vasm.o" ".\lwmf\include\lwmf_hardware_vasm.o" -o $(PROG) -lamiga

adf: $(PROG)
	echo $(PROG) > startup-sequence
	xdftool $(ADF) format DemoDisk
	xdftool $(ADF) boot install
	xdftool $(ADF) makedir S
	xdftool $(ADF) write $(PROG) $(PROG)
	xdftool $(ADF) write $(GFXDIR) $(GFXDIR)
	xdftool $(ADF) write startup-sequence S/startup-sequence
	xdftool $(ADF) list
	del /Q startup-sequence 2>NUL