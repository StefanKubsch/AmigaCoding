vasmm68k_mot -Fhunk -showopt -o ".\lwmf\include\lwmf_hardware_vasm.o" ".\lwmf\src\lwmf_hardware_vasm.s"
vasmm68k_mot -Fhunk -showopt -o ".\lwmf\include\lwmf_math_vasm.o" ".\lwmf\src\lwmf_math_vasm.s"

vc -O4 Copper.c ".\lwmf\include\lwmf_hardware_vasm.o" ".\lwmf\include\lwmf_math_vasm.o" -o Copper -lamiga    