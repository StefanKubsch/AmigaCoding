vasmm68k_mot -Fhunk -o ".\lwmf\include\lwmf_WaitVertBlank.o" ".\lwmf\src\lwmf_WaitVertBlank.s"
vc -O4 Demo.c ".\lwmf\include\lwmf_WaitVertBlank.o" -o Demo -lmieee -lamiga    