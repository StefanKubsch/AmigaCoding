_lwmf_WaitVertBlank:
.loop: 
	move.l $DFF004,d0
	and.l #$1FF00,d0
	cmp.l #303<<8,d0
	bne.b .loop
.loop2: 
	move.l $DFF004,d0
	and.l #$1FF00,d0
	cmp.l #303<<8,d0
	beq.b .loop2
	rts

	public	_lwmf_WaitVertBlank