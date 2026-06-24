        SECTION SECTION AssetData,DATA

        XDEF _RotoImage
        XDEF _RotoImage_end

        CNOP 0,2

_RotoImage:
        incbin "gfx/128x128_ham.iff"
_RotoImage_end: