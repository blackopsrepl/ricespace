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
end
