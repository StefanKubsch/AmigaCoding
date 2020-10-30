_lwmf_WaitBlitter:
    btst.b #14-8,$DFF000 + $02(a1) ; check DMAB_BLTDONE against DMACONR
.waitblit2:
    btst.b #14-8,$DFF000 + $02(a1) ; twice, bug in A1000
    bne .waitblit2
    rts

	public _lwmf_WaitBlitter