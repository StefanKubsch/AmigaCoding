vasmm68k_mot -Fhunk -showopt -o ".\lwmf\include\lwmf_hardware_vasm.o" ".\lwmf\lwmf_hardware_vasm.s"
vasmm68k_mot -Fhunk -showopt -o ".\lwmf\include\lwmf_math_vasm.o" ".\lwmf\lwmf_math_vasm.s"

vasmm68k_mot -Fcdef -o ".\lwmf\lwmf_Defines.h" ".\lwmf\lwmf_hardware_vasm.s"

vasmm68k_mot -Fhunk -showopt -o "SineScroller_vasm.o" "SineScroller_vasm.s"

vc -O4 -speed -final -sc -cpu=68000 SineScroller.c "SineScroller_vasm.o" ".\lwmf\include\lwmf_hardware_vasm.o" ".\lwmf\include\lwmf_math_vasm.o" -o SineScroller -lamiga