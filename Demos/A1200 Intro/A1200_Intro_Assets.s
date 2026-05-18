        SECTION SECTION AssetData,DATA

        XDEF _TextLogo
        XDEF _TextLogo_end

        XDEF _SineScroller
        XDEF _SineScroller_end

        XDEF _ModMusic
        XDEF _ModMusic_end

_TextLogo:
        incbin "gfx/Logo.iff"
_TextLogo_end:

_SineScroller:
        incbin "gfx/ScrollFont.bsh"
_SineScroller_end:

_ModMusic:
        incbin "sfx/beamsoflight.mod"
_ModMusic_end: