
require 'logger'


class MyLogger
  # Create a class variable to hold the logger instance
  @@logger = Logger.new('my_log_file.log')

  # Define class methods to access the logger
  def self.log
    @@logger
  end
end

def filter_lines_by_line_numbers(reader, target, file, linenums)
  line_num = 0
  start_line_num = nil
  select_rest = false
  lines = []

  file.each do |line|
    line_num += 1
    if select_rest || (select_rest = linenums[0] == Float::INFINITY)
      start_line_num ||= line_num
      lines << line
    else
      if linenums[0] == line_num
        start_line_num ||= line_num
        linenums.shift
        lines << line
      end
      return [lines, start_line_num || 1] if linenums.empty?
    end
  end
  [lines, start_line_num || 1]
end


def get_lines(attrs)
  return [] unless attrs.key?('lines')

  lines = attrs['lines']
  return [] unless lines

  linenums = Set.new
  filtered = false
  (lines.include?(',') ? lines.split(',') : lines.split(';'))
    .reject(&:empty?)
    .each do |linedef|
      filtered = true
      delim = linedef.index('..')
      from = nil
      if delim
        from = linedef[0, delim]
        to = linedef[(delim + 2)..]
        if (to = Integer(to, 10) rescue -1) > 0
          if (from = Integer(from, 10) rescue -1) > 0
            from.upto(to) { |i| linenums.add(i) }
          end
        elsif to == -1 && (from = Integer(from, 10) rescue -1) > 0
          linenums.add(from)
          linenums.add(Float::INFINITY)
        end
      elsif (from = Integer(linedef, 10) rescue -1) > 0
        linenums.add(from)
      end
    end
  linenums.to_a.sort
end

def get_tags(attrs)
  if attrs.key?('tag')
    tag = attrs['tag']
    if tag && tag != '!'
      return tag[0] == '!' ? { tag[1..-1] => false } : { tag => true }
    end
  elsif attrs.key?('tags')
    tags = attrs['tags']
    if tags
      result = {}
      any = false
      separator = tags.include?(',') ? ',' : ';'
      tags.split(separator).each do |tag|
        if tag && tag != '!'
          any = true
          result[tag[0] == '!' ? tag[1..-1] : tag] = tag[0] != '!'
        end
      end
      return result if any
    end
  end
end

def filter_lines_by_tags(reader, target, file, tags)
  globstar = tags['**']
  star = tags['*']
  selecting = nil


  selecting_default = select_default globstar, star, tags

  lines = []
  tag_stack = []
  found_tags = []
  active_tag = nil
  line_num = 0
  start_line_num = nil
  file.each do |line|
    line_num += 1
    m = line.match(/\b(?:tag|(e)nd)::(\S+?)\[\](?=$|[ \r])/m)
    if line.include?('::') && line.include?('[]') && m
      this_tag = m[2]
      if m[1]
        if this_tag == active_tag
          tag_stack.shift
          active_tag, selecting = tag_stack.empty? ? [nil, selecting_default] : tag_stack[0]
        elsif tags.key?(this_tag)
          idx = tag_stack.index { |name, _, _| name == this_tag }
          if idx
            tag_stack.delete_at(idx)
            message = "mismatched end tag (expected '#{active_tag}' but found '#{this_tag}') at line #{line_num} of include file: #{target})"
            MyLogger.log.warn(message)
          else
            message = "unexpected end tag '#{this_tag}' at line #{line_num} of include file: #{target}"
            MyLogger.log.warn(message)
          end
        end
      elsif tags.key?(this_tag)
        found_tags.push(this_tag)
        tag_stack.unshift([active_tag = this_tag, selecting = tags[this_tag], line_num])
      elsif wildcard.nil?
        selecting = active_tag && !selecting ? false : wildcard
        tag_stack.unshift([active_tag = this_tag, selecting, line_num])
      end
    elsif selecting
      start_line_num ||= line_num
      lines.push(line)
    end
  end

  if tag_stack.any?
    tag_stack.each do |tag_name, _, tag_line_num|
      message = "detected unclosed tag '#{tag_name}' starting at line #{tag_line_num} of include file: #{target}" #, reader.create_include_cursor(file, target, tag_line_num))
      MyLogger.log.warn(message)
    end
  end

  found_tags.each { |name| tags.delete(name) }
  if tags.any?
    message = "tag#{tags.size > 1 ? 's' : ''} '#{tags.keys.join(', ')}' not found in include file: #{target}"
    MyLogger.log.warn(message)
  end

  [lines, start_line_num || 1]
end

def map_contains_value(map, value)
  map.values.include?(value)
end

def select_default(globstar, star, tags)
  if globstar.nil?
    if star.nil?
      !map_contains_value(tags, true)
    else
      wildcard = star if star
      if tags.keys.next != '*'
        selecting_default = false
      else
        wildcard = !wildcard if wildcard
        selecting_default = wildcard
      end
      tags.delete('*')
    end
  else
    tags.delete('**')
    selecting_default = globstar
    if star.nil?
      wildcard = true if !globstar && tags.values.first == false
    else
      tags.delete('*')
      wildcard = star
    end
  end
end
