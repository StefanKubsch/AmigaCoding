vasmm68k_mot -Fhunk -showopt -o ".\lwmf\include\lwmf_hardware_asm.o" ".\lwmf\src\lwmf_hardware_asm.s"
vasmm68k_mot -Fhunk -showopt -o ".\lwmf\include\lwmf_math_asm.o" ".\lwmf\src\lwmf_math_asm.s"

vc -O4 Copper.c ".\lwmf\include\lwmf_hardware_asm.o" ".\lwmf\include\lwmf_math_asm.o" -o Copper -lamiga    