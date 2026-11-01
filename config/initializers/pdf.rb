# Prawn and rqrcode are not always auto-required by Bundler in all environments.
# Explicitly require them at boot so LabelPdf can use them without a top-level require.
require "prawn"
require "prawn/table"
require "rqrcode"
