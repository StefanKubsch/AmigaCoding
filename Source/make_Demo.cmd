vasmm68k_mot -Fhunk -showopt -o ".\lwmf\include\lwmf_Hardware_ASM.o" ".\lwmf\src\lwmf_Hardware_ASM.s"
vc -O4 Demo.c ".\lwmf\include\lwmf_Hardware_ASM.o" -o Demo -lmieee -lamiga