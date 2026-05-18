ADF=demo.adf
PROG=A1200_Intro
VC_TARGET=+kick13
ASM_HUNK_FLAGS=-Fhunk -kick1hunks -showopt
VBCC_NDK_INCLUDE=-I"%VBCC%"/NDK39/Include/include_h

LWMF_HW_SRC=.\lwmf\lwmf_hardware_vasm.s
LWMF_HW_OBJ=.\lwmf\include\lwmf_hardware_vasm.o
LWMF_HW_DEFS=.\lwmf\lwmf_Defines.h
LWMF_PTPLAYER_SRC=.\lwmf\ptplayer\ptplayer.asm
LWMF_PTPLAYER_OBJ=.\lwmf\include\lwmf_ptplayer.o

ASSETS_SRC=A1200_Intro_Assets.s
ASSETS_OBJ=A1200_Intro_Assets.o

C_SRC=A1200_Intro.c

.PHONY: all build adf clean-objs

all: build

build: clean-objs $(PROG)

clean-objs:
	if exist *.o del /Q *.o
	if exist .\lwmf\include\*.o del /Q .\lwmf\include\*.o

$(LWMF_HW_OBJ): $(LWMF_HW_SRC)
	vasmm68k_mot $(ASM_HUNK_FLAGS) -o "$(LWMF_HW_OBJ)" "$(LWMF_HW_SRC)"

$(LWMF_HW_DEFS): $(LWMF_HW_SRC)
	vasmm68k_mot -Fcdef -o "$(LWMF_HW_DEFS)" "$(LWMF_HW_SRC)"

$(LWMF_PTPLAYER_OBJ): $(LWMF_PTPLAYER_SRC)
	vasmm68k_mot $(ASM_HUNK_FLAGS) -o "$(LWMF_PTPLAYER_OBJ)" "$(LWMF_PTPLAYER_SRC)"

$(ASSETS_OBJ): $(ASSETS_SRC)
	vasmm68k_mot $(ASM_HUNK_FLAGS) -o "$(ASSETS_OBJ)" "$(ASSETS_SRC)"

$(PROG): $(C_SRC) $(ASSETS_OBJ) $(LWMF_HW_OBJ) $(LWMF_PTPLAYER_OBJ) $(LWMF_HW_DEFS) $(SHARED_H)
	vc $(VC_TARGET) $(VBCC_NDK_INCLUDE) -O4 -speed -final -sd -sc -cpu=68000 $(C_SRC) "$(ASSETS_OBJ)" "$(LWMF_HW_OBJ)" "$(LWMF_PTPLAYER_OBJ)" -o $(PROG) -lamiga

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