vasmm68k_mot -Fhunk -o ".\lwmf\include\lwmf_Hardware_ASM.o" ".\lwmf\src\lwmf_Hardware_ASM.s"
vc -O4 Copper.c ".\lwmf\include\lwmf_Hardware_ASM.o" -o Copper -lamiga    