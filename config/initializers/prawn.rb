# Labels use Prawn's built-in fonts, which cover Windows-1252 (enough for Danish).
# LabelRenderer#safe already strips anything outside that range, so Prawn's
# internationalization warning is expected noise on every label print.
Prawn::Fonts::AFM.hide_m17n_warning = true
