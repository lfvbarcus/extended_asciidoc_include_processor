require 'asciidoctor'
require_relative 'extended_reader'
require_relative 'other_processor'
# IncludeProcessor to handle https like includes with or without auth.
# Currently, only OpenURI is supported
Asciidoctor::Extensions.register do
  include_processor OAuthExtensionIncludeProcessor
  include_processor OtherIncludeProcessor
end

class OAuthExtensionIncludeProcessor < Asciidoctor::Extensions::IncludeProcessor

  # Specifies that this IncludeProcessor only handles http/https targets
  def handles? target
    target.start_with? 'http://', 'https://'
  end

  def process(_doc, reader, target, attributes)
    unless include_allowed? target, reader
      reader.unshift_line("link:#{target}[]")
      return
    end

    if (max_depth = reader.exceeded_max_depth?)
      logger.error "#{reader.line_info}: maximum include depth of #{max_depth} exceeded"
      return
    end

    token = resolve_token attributes

    http_provider = resolve_http_provider attributes

    resolved_content = resolve_content target, token, http_provider

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

    reader.push_include included_content, target, target, 1, attributes
  end

  def include_allowed?(target, reader)
    doc = reader.document

    return false if doc.safe >= ::Asciidoctor::SafeMode::SECURE
    return false if doc.attributes.fetch('max-include-depth', 64).to_i < 1
    return false if target_http?(target) && !doc.attributes.key?('allow-uri-read')

    true
  end

  def target_http?(target)
    # First do a fast test, then try to parse it.
    target.downcase.start_with?('http://', 'https://') \
      && URI.parse(target).is_a?(URI::HTTP)
  rescue URI::InvalidURIError
    false
  end

  # this should return the GITLAB_TOKEN and/or the oauth_token in an array.
  # The content of the returning array must never be logged.
  # TODO: Should one of the tokens have precedence instead?
  def resolve_token(attributes)
    gitlab_token = ENV['GITLAB_TOKEN']
    include_token = attributes['oauth_token']

    combine_variables gitlab_token, include_token
  end

  def combine_variables(var1, var2)
    if var1.nil? && var2.nil?
      ''
    elsif !var1.nil? && !var2.nil?
      [var1, var2]
    elsif !var1.nil?
      var1
    else
      var2
    end
  end

  def resolve_content(target, token, http_provider = "OpenURI")
    unless http_provider == "OpenURI" || http_provider == "HTTParty"
      raise ArgumentError, "Invalid http_provider value. Must be HTTParty or OpenURI."
    end

    if(http_provider == "OpenURI")
      resolve_openuri target, token
    else
      resolve_httparty target, token
    end

  end

  def resolve_openuri(target, token)
    if target.start_with? 'https://'
      if token.empty?
        (::OpenURI.open_uri target).readlines
      else
        (::OpenURI.open_uri target, 'Authorization' => "Bearer #{token}").readlines
      end
    else
      MyLogger.log.warn("Not able to parse URI. Are you using http instead of https?")
    end
  end

  def resolve_httparty(target, token)
    raise ArgumentError, "Not implemented yet"
  end

  def resolve_http_provider(attributes)
    http_provider = attributes.fetch('http_provider', 'OpenURI')
  end

end
