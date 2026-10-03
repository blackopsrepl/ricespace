# frozen_string_literal: true

# The site's own helpers.
#
# `author_stylesheet` is here rather than in a view because it is the one place in
# the application that writes raw HTML, and it deserves a name and a reason.
#
# Rails escapes a value interpolated with `<%= %>`, which inside a `<style>` element
# turns `font-family: "Courier New"` into `font-family: &quot;Courier New&quot;` —
# the declaration then parses as something else entirely, and the page quietly loses
# a rule its author wrote. The stylesheet must be emitted raw.
#
# It is safe to do so because PageCss refuses any declaration or selector containing
# `<`, so a sheet cannot close the element it is written into: `content:
# "</style><script>"` is dropped, not escaped. Both halves of that are pinned by
# profile_markup_test.rb and page_css_test.rb.
module ApplicationHelper
  def author_stylesheet(css)
    return if css.blank?

    tag.style(raw(css)) # rubocop:disable Rails/OutputSafety
  end

  # A colour for a `style` attribute, or the fallback when the page has not said.
  #
  # The value comes from a page's own stylesheet, so it is passed through a strict
  # shape check before it reaches the attribute — a CSS colour value is a short
  # vocabulary, and anything outside it is not a colour.
  def colour_style(colour, fallback:)
    value = colour.to_s.match?(PageThumbnail::COLOUR) ? colour : fallback
    "color: #{value}".html_safe
  end

  def background_style(colour)
    value = colour.to_s.match?(PageThumbnail::COLOUR) ? colour : "transparent"
    "background-color: #{value}".html_safe
  end
end
