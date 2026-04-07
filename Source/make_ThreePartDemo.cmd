vasmm68k_mot -Fhunk -showopt -o ".\lwmf\include\lwmf_hardware_vasm.o" ".\lwmf\lwmf_hardware_vasm.s"
vasmm68k_mot -Fhunk -showopt -o ".\lwmf\include\lwmf_math_vasm.o" ".\lwmf\lwmf_math_vasm.s"

vasmm68k_mot -Fhunk -showopt -o ".\lwmf\include\lwmf_ptplayer.o" ".\lwmf\ptplayer\ptplayer.asm"

vasmm68k_mot -Fcdef -o ".\lwmf\lwmf_Defines.h" ".\lwmf\lwmf_hardware_vasm.s"

vc -O4 -speed -final -sc -cpu=68000 ThreePartDemo.c ".\lwmf\include\lwmf_hardware_vasm.o" ".\lwmf\include\lwmf_math_vasm.o" ".\lwmf\include\lwmf_ptplayer.o" -o ThreePartDemo -lamiga