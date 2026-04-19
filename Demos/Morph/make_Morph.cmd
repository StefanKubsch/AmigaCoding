vasmm68k_mot -Fhunk -showopt -o ".\lwmf\include\lwmf_hardware_vasm.o" ".\lwmf\lwmf_hardware_vasm.s"
vasmm68k_mot -Fhunk -showopt -o ".\lwmf\include\lwmf_math_vasm.o" ".\lwmf\lwmf_math_vasm.s"

vasmm68k_mot -Fcdef -o ".\lwmf\lwmf_Defines.h" ".\lwmf\lwmf_hardware_vasm.s"

rem vasmm68k_mot -Fhunk -showopt -o "Morph_vasm.o" "Morph_vasm.s"

rem vc -O4 -speed -final -sc -cpu=68000 Morph.c ".\lwmf\include\lwmf_hardware_vasm.o" ".\lwmf\include\lwmf_math_vasm.o" "Morph_vasm.o" -o Morph -lamiga
vc -O4 -speed -final -sc -cpu=68000 Morph.c ".\lwmf\include\lwmf_hardware_vasm.o" ".\lwmf\include\lwmf_math_vasm.o" -o Morph -lamiga