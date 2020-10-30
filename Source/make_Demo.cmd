vasmm68k_mot -Fhunk -o ".\lwmf\include\lwmf_WaitVertBlank.o" ".\lwmf\src\lwmf_WaitVertBlank.s"
vasmm68k_mot -Fhunk -o ".\lwmf\include\lwmf_WaitBlitter.o" ".\lwmf\src\lwmf_WaitBlitter.s"

vc -O4 Demo.c ".\lwmf\include\lwmf_WaitVertBlank.o" ".\lwmf\include\lwmf_WaitBlitter.o" -o Demo -lmieee -lamiga    