ADF=demo.adf
PROG=Rotozoomer
KICK13_ADF=demo_k13.adf
KICK13_PROG=Rotozoomer_k13
NDK39_INCLUDE_H=C:/vbcc/ndk39/include/include_h

SHARED_SCRIPT=Rotozoomer_shared_defs.py
SHARED_H=Rotozoomer_shared.h
SHARED_I=Rotozoomer_shared.i

LWMF_HW_SRC=.\lwmf\lwmf_hardware_vasm.s
LWMF_HW_OBJ=.\lwmf\include\lwmf_hardware_vasm.o
LWMF_HW_OBJ_K13=.\lwmf\include\lwmf_hardware_vasm_k13.o
LWMF_HW_DEFS=.\lwmf\lwmf_Defines.h

ASSETS_SRC=Rotozoomer_Assets.s
ASSETS_OBJ=Rotozoomer_Assets.o
ASSETS_OBJ_K13=Rotozoomer_Assets_k13.o

ASM_SRC=Rotozoomer_vasm.s
ASM_OBJ=Rotozoomer_vasm.o
ASM_OBJ_K13=Rotozoomer_vasm_k13.o
C_SRC=Rotozoomer.c

.PHONY: all build build-kick13 adf adf-kick13 clean-objs

all: build

build: clean-objs $(PROG)

build-kick13: clean-objs $(KICK13_PROG)

clean-objs:
	if exist *.o del /Q *.o
	if exist .\lwmf\include\*.o del /Q .\lwmf\include\*.o

$(SHARED_H) $(SHARED_I): $(SHARED_SCRIPT)
	python $(SHARED_SCRIPT)

$(LWMF_HW_OBJ): $(LWMF_HW_SRC)
	vasmm68k_mot -Fhunk -showopt -o "$(LWMF_HW_OBJ)" "$(LWMF_HW_SRC)"

$(LWMF_HW_OBJ_K13): $(LWMF_HW_SRC)
	vasmm68k_mot -Fhunk -kick1hunks -showopt -o "$(LWMF_HW_OBJ_K13)" "$(LWMF_HW_SRC)"

$(LWMF_HW_DEFS): $(LWMF_HW_SRC)
	vasmm68k_mot -Fcdef -o "$(LWMF_HW_DEFS)" "$(LWMF_HW_SRC)"

$(ASM_OBJ): $(ASM_SRC) $(SHARED_I)
	vasmm68k_mot -Fhunk -showopt -o "$(ASM_OBJ)" "$(ASM_SRC)"

$(ASM_OBJ_K13): $(ASM_SRC) $(SHARED_I)
	vasmm68k_mot -Fhunk -kick1hunks -showopt -o "$(ASM_OBJ_K13)" "$(ASM_SRC)"

$(ASSETS_OBJ): $(ASSETS_SRC)
	vasmm68k_mot -Fhunk -showopt -o "$(ASSETS_OBJ)" "$(ASSETS_SRC)"

$(ASSETS_OBJ_K13): $(ASSETS_SRC)
	vasmm68k_mot -Fhunk -kick1hunks -showopt -o "$(ASSETS_OBJ_K13)" "$(ASSETS_SRC)"

$(PROG): $(C_SRC) $(ASM_OBJ) $(ASSETS_OBJ) $(LWMF_HW_OBJ) $(LWMF_HW_DEFS) $(SHARED_H)
	vc -O4 -speed -final -sd -sc -cpu=68000 $(C_SRC) "$(ASM_OBJ)" "$(ASSETS_OBJ)" "$(LWMF_HW_OBJ)" -o $(PROG) -lamiga

$(KICK13_PROG): $(C_SRC) $(ASM_OBJ_K13) $(ASSETS_OBJ_K13) $(LWMF_HW_OBJ_K13) $(LWMF_HW_DEFS) $(SHARED_H)
	vc +kick13 -O4 -speed -final -sd -sc -cpu=68000 -I"$(NDK39_INCLUDE_H)" $(C_SRC) "$(ASM_OBJ_K13)" "$(ASSETS_OBJ_K13)" "$(LWMF_HW_OBJ_K13)" -o $(KICK13_PROG) -lamiga

shrink: $(PROG)
	shrinkler -o "$(PROG)" "$(PROG)"

adf: $(PROG)
	echo $(PROG) > startup-sequence
	xdftool $(ADF) format DemoDisk
	xdftool $(ADF) boot install
	xdftool $(ADF) makedir S
	xdftool $(ADF) write $(PROG) $(PROG)
	xdftool $(ADF) write startup-sequence S/startup-sequence
	xdftool $(ADF) list
	del /Q startup-sequence 2>NUL

adf-kick13: $(KICK13_PROG)
	echo $(KICK13_PROG) > startup-sequence
	xdftool $(KICK13_ADF) format DemoDisk
	xdftool $(KICK13_ADF) boot install
	xdftool $(KICK13_ADF) makedir S
	xdftool $(KICK13_ADF) write $(KICK13_PROG) $(KICK13_PROG)
	xdftool $(KICK13_ADF) write startup-sequence S/startup-sequence
	xdftool $(KICK13_ADF) list
	del /Q startup-sequence 2>NUL