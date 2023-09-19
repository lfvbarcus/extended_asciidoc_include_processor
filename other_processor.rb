require 'logger'
require_relative 'oauth_extend'
require_relative 'tags_and_lines.rb'

#Include processor to handle file includes
class OtherIncludeProcessor < Asciidoctor::Extensions::IncludeProcessor

  # Specifies that this IncludeProcessor only handles targets without http/https
  def handles? target
    !target.start_with? 'https://', 'https://'
  end

  def process(_doc, reader, target, attributes)
    print 'in local files include processor'

    resolved_content = File.readlines(target)

    if(resolved_content)

      included_content = nil
      lines = get_lines(attributes)
      tags = get_tags(attributes)
      start_line_num = nil

      if(lines && !lines.empty?)
        included_content, start_line_num = filter_lines_by_line_numbers(reader, target, resolved_content, lines)
      elsif(tags)
        included_content, start_line_num = filter_lines_by_tags(reader, target, resolved_content, tags)
      else
        included_content = resolved_content
      end
    end

    reader.push_include(included_content, target, target, start_line_num, attributes)
  end
end
