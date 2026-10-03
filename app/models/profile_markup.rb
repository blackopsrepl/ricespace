# frozen_string_literal: true

# The trust boundary between a profile author's markup and every page that
# renders it.
#
# Authors get the presentational vocabulary the old social networks gave them —
# text, headings, links, images, tables, marquee-era tags, inline colours and
# inline CSS — declared as an allowlist. Everything that can execute, navigate
# the browser, or restyle the site is absent from the allowlist and is pruned
# together with its contents: script, style, iframe, object, embed, form and
# friends, inline event handler attributes, and URLs that are not http(s),
# site-relative or anchors.
#
# Sanitising happens on render, not on save: the stored column always holds what
# the author wrote, so tightening the allowlist later applies to existing
# profiles without a data migration. Nothing reaches a page except through
# .render.
class ProfileMarkup
  # Ceiling on the document handed to the parser, in bytes. A profile page is a
  # page, not a payload: this bounds the parse cost of every render of it.
  MAX_BYTES = 100_000

  # Tags a profile may use, including the deprecated presentational set that is
  # the visual language of profiles from the era RiceSpace imitates.
  TAGS = %w[
    a abbr acronym address b bdi bdo big blink blockquote br caption center cite
    code col colgroup dd del details dfn div dl dt em fieldset figcaption figure
    font h1 h2 h3 h4 h5 h6 hr i img ins kbd legend li mark marquee nobr ol p pre
    q rb rp rt ruby s samp small span strike strong sub summary sup table tbody
    td tfoot th thead time tr tt u ul var wbr
  ].freeze

  # Attributes a profile may set. `style` is permitted because inline CSS is how
  # profiles are decorated; the stylesheet parser strips declarations that would
  # take a profile out of its own column (position, z-index, behaviour, and any
  # URL that is not an image fetch).
  ATTRIBUTES = %w[
    abbr align alt axis bgcolor border cellpadding cellspacing cite class color
    cols colspan datetime dir face headers height href hspace lang name nowrap
    rel rev rowspan rules scope size span src start style summary title valign
    value vspace width
  ].freeze

  # Where a link may point: the open web, this site, or an anchor on the page.
  LINK_URL = %r{\A(?:\#|/(?!/)|https?://|//|mailto:)}i
  # Where an image may come from. Same as links, minus mailto.
  IMAGE_URL = %r{\A(?:\#|/(?!/)|https?://|//)}i

  # `prune: true` drops disallowed elements together with everything inside
  # them, so a <script> or <iframe> disappears entirely rather than leaving its
  # source text behind as visible copy.
  SANITIZER = Rails::HTML5::SafeListSanitizer.new(prune: true)

  def self.render(html)
    new(html).to_html
  end

  def initialize(html)
    @html = html.to_s
  end

  # Returns the profile markup as a String marked safe for interpolation into a
  # template.
  def to_html
    cleaned = SANITIZER.sanitize(document, tags: TAGS, attributes: ATTRIBUTES)
    fragment = Loofah.html5_fragment(cleaned)
    enforce_url_policy(fragment)
    mark_outbound_links(fragment)
    fragment.to_html.html_safe
  end

  private
    def document
      text = @html.scrub
      return "" if text.strip.empty?
      return text if text.bytesize <= MAX_BYTES

      # Cut to the cap, then drop whatever character the cut split rather than
      # replacing it: a replacement character is three bytes, which would put the
      # document back over the cap it was just trimmed to.
      text = text.byteslice(0, MAX_BYTES)
      text = text.byteslice(0, text.bytesize - 1) until text.empty? || text.valid_encoding?
      text
    end

    # A tag can survive the allowlist with an attribute whose value the browser
    # would otherwise follow somewhere we did not intend. Anything that is not a
    # link, an image, or an on-page anchor loses the attribute.
    def enforce_url_policy(fragment)
      fragment.css("a[href]").each do |node|
        node.remove_attribute("href") unless node["href"].match?(LINK_URL)
      end

      fragment.css("img[src]").each do |node|
        node.remove_attribute("src") unless node["src"].match?(IMAGE_URL)
      end
    end

    # Links leaving a profile are the author's, not ours: tell search engines and
    # the receiving page that the author does not endorse the target.
    def mark_outbound_links(fragment)
      fragment.css("a[href]").each do |node|
        rel = node["rel"].to_s.split
        node["rel"] = (rel + %w[nofollow ugc noopener]).uniq.join(" ")
      end
    end
end
