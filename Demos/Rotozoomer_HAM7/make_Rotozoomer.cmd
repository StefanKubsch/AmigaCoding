vasmm68k_mot -Fhunk -showopt -o ".\lwmf\include\lwmf_hardware_vasm.o" ".\lwmf\lwmf_hardware_vasm.s"

vasmm68k_mot -Fcdef -o ".\lwmf\lwmf_Defines.h" ".\lwmf\lwmf_hardware_vasm.s"

vasmm68k_mot -Fhunk -showopt -o "Rotozoomer_vasm.o" "Rotozoomer_vasm.s"

vc -O4 -speed -final -sd -sc -cpu=68000 Rotozoomer.c "Rotozoomer_vasm.o" ".\lwmf\include\lwmf_hardware_vasm.o" -o Rotozoomer -lamiga