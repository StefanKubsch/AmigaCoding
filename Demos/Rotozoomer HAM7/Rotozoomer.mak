ADF=demo.adf
PROG=Rotozoomer
GFXDIR=gfx

SHARED_SCRIPT=Rotozoomer_shared_defs.py
SHARED_H=Rotozoomer_shared.h
SHARED_I=Rotozoomer_shared.i

LWMF_HW_SRC=.\lwmf\lwmf_hardware_vasm.s
LWMF_HW_OBJ=.\lwmf\include\lwmf_hardware_vasm.o
LWMF_HW_DEFS=.\lwmf\lwmf_Defines.h

ASM_SRC=Rotozoomer_vasm.s
ASM_OBJ=Rotozoomer_vasm.o
C_SRC=Rotozoomer.c

.PHONY: all build adf

all: build

build: $(PROG)

$(SHARED_H) $(SHARED_I): $(SHARED_SCRIPT)
	python $(SHARED_SCRIPT)

$(LWMF_HW_OBJ): $(LWMF_HW_SRC)
	vasmm68k_mot -Fhunk -showopt -o "$(LWMF_HW_OBJ)" "$(LWMF_HW_SRC)"

$(LWMF_HW_DEFS): $(LWMF_HW_SRC)
	vasmm68k_mot -Fcdef -o "$(LWMF_HW_DEFS)" "$(LWMF_HW_SRC)"

$(ASM_OBJ): $(ASM_SRC) $(SHARED_I)
	vasmm68k_mot -Fhunk -showopt -o "$(ASM_OBJ)" "$(ASM_SRC)"

$(PROG): $(C_SRC) $(ASM_OBJ) $(LWMF_HW_OBJ) $(LWMF_HW_DEFS) $(SHARED_H)
	vc -O4 -speed -final -sd -sc -cpu=68000 $(C_SRC) "$(ASM_OBJ)" "$(LWMF_HW_OBJ)" -o $(PROG) -lamiga

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