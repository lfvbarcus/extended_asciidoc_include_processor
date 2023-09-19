require 'asciidoctor'
require_relative 'oauth_extend'

input_file = 'index.adoc'
output_file = 'output.html'

Asciidoctor.convert_file(input_file, to_file: output_file, safe: :unsafe, attributes: {
  'allow-uri-read' => true
})
