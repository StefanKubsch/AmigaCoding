; Various assembler functions for lwmf
; Code is compatible with Motorola syntax as provided by vbcc

;
; __reg("d0") ULONG lwmf_Random(void);
;

_lwmf_Random:
    move.l  seed,d0
    addq.l  #5,d0
    rol.l   d0,d0
    move.l  d0,seed
    rts    

    public _lwmf_Random
    
seed:
    dc.l    $12345678