# frozen_string_literal: true

# The stylesheet a profile author writes for their own page.
#
# This is the part of a profile that was never a rich-text field: a real
# stylesheet, parsed and re-serialised, applied after the site's own styles so
# that it can restyle the whole page — including the site's chrome — exactly as
# profile stylesheets did when the layout *was* the product.
#
# What is removed is what can fetch or execute:
#
#   - at-rules (`@import`, `@charset`, `@media`, …). `@import` pulls a remote
#     stylesheet in, which is a load the author does not get to make; the rest
#     are dropped with it because a stylesheet that can only contain rules is a
#     smaller thing to reason about.
#   - comments, as the sites of the era stripped them too.
#   - any declaration whose value carries a `url()` that is not http(s),
#     site-relative or a fragment, and any declaration using `expression()`,
#     `behavior` or `-moz-binding`.
#
# Everything else survives: `position`, `z-index`, `display`, `visibility`,
# `overflow`, `!important`, arbitrary selectors, nesting — the vocabulary the
# layouts of the era were actually built from.
class PageCss
  # A stylesheet is a page's whole look, not a payload.
  MAX_BYTES = 50_000

  # Where a url() may point. No `javascript:`, no `data:`, no scheme-relative
  # trickery: a scheme and a host, an absolute path, or a fragment for filters.
  URL_POLICY = %r{\A(?:\#|https?://|//|/(?!/))}i

  # Declarations that are a scripting mechanism in one engine or another.
  FORBIDDEN_PROPERTIES = %w[behavior -moz-binding].freeze
  FORBIDDEN_VALUE = /expression\s*\(/i

  def self.sanitize(css)
    new(css).to_s
  end

  # Scrub a style="" attribute. Same policy as a whole sheet, one declaration
  # list at a time, so inline styles and stylesheets cannot disagree.
  def self.sanitize_declarations(css)
    text = css.to_s.scrub
    return "" if text.strip.empty?

    Crass.parse_properties(text.byteslice(0, MAX_BYTES))
      .filter_map { |declaration| render_declaration(declaration) }
      .join(" ")
  end

  # Render one declaration as `name: value`, or nil when it must not survive.
  def self.render_declaration(declaration)
    return nil unless declaration[:node] == :property

    name = declaration[:name].to_s
    value = declaration[:value].to_s
    return nil if FORBIDDEN_PROPERTIES.include?(name.downcase)
    return nil if value.match?(FORBIDDEN_VALUE)
    return nil unless urls_allowed?(declaration[:children])

    rendered = "#{name}: #{value.strip}#{' !important' if declaration[:important]};"

    # A `<` cannot be part of a declaration, and the sanitised sheet is
    # interpolated into a <style> element: `content: "</style><script>"` would
    # otherwise close that element and become markup.
    return nil if rendered.include?("<")

    rendered
  end

  # False when the declaration carries a url() the policy refuses. A declaration
  # is dropped whole rather than degraded: `background: url(javascript:…)` must
  # not become `background:`.
  def self.urls_allowed?(children)
    Array(children).all? do |token|
      case token[:node]
      when :bad_url then false
      when :url then token[:value].to_s.match?(URL_POLICY)
      else true
      end
    end
  end

  def initialize(css)
    @css = css.to_s
  end

  def to_s
    text = @css.scrub.byteslice(0, MAX_BYTES)
    return "" if text.strip.empty?

    Crass.parse(text).filter_map { |node| render(node) }.join("\n")
  end

  private
    # One rule, rebuilt from its parsed parts. Comments and anything
    # unrecognised fall out here, and a selector the parser could not make sense
    # of — the stray `body` after an unclosed rule — is refused rather than
    # re-emitted, so a broken sheet cannot quietly restyle a new selector.
    def render(node)
      return nil unless node[:node] == :style_rule

      selector = node.dig(:selector, :value).to_s.strip
      return nil if selector.empty?

      # A selector cannot contain braces or a semicolon; if one does, the sheet
      # was malformed around an unclosed rule and this "selector" is the tail of
      # the previous one. Refusing it keeps a broken sheet from quietly
      # restyling something its author never named. `<` is refused for the same
      # reason as in a declaration: this sheet is written into a <style> element.
      return nil if selector.match?(/[{};<]/)

      declarations = Array(node[:children]).filter_map { |child| self.class.render_declaration(child) }
      return nil if declarations.empty?

      "#{selector} { #{declarations.join(' ')} }"
    end
end
