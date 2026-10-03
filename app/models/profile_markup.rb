# frozen_string_literal: true

# The trust boundary between a profile author's markup and every page that
# renders it.
#
# A profile is a page the author lays out themselves, and it carries two kinds of
# thing that are not cleaned the same way:
#
#   * **Content** — the markup inside the page's column. Cleaned on render
#     against an allowlist: the presentational vocabulary profiles are built
#     from, including the deprecated tags of the era, and nothing that can
#     execute, navigate, embed or fetch.
#   * **Its stylesheet** — `<style>` blocks, which are *not* scoped to the column.
#     They are parsed and re-serialised by PageCss, keeping `position`,
#     `z-index`, `visibility` and the rest, because a profile layout is exactly
#     that: rules that restyle the whole page, including the site's chrome.
#
# The two come back together, as Rendered, because a page that shows the first
# without the second is not the page its author wrote.
#
# Cleaning happens on render, not on save: the stored column always holds what
# the author wrote, so a tightened rule applies to existing pages with no data
# migration, and nothing reaches a page except through .render.
class ProfileMarkup
  # Ceiling on the document handed to the parser, in bytes.
  MAX_BYTES = 100_000

  # Tags a profile may use, including the deprecated presentational set that is
  # the visual language of profiles from the era RiceSpace imitates. `style` is
  # absent: it is not content, it is extracted as a stylesheet before this
  # allowlist is applied.
  TAGS = %w[
    a abbr acronym address b bdi bdo big blink blockquote br caption center cite
    code col colgroup dd del details dfn div dl dt em fieldset figcaption figure
    font h1 h2 h3 h4 h5 h6 hr i img ins kbd legend li mark marquee nobr ol p pre
    q rb rp rt ruby s samp small span strike strong sub summary sup table tbody
    td tfoot th thead time tr tt u ul var wbr
  ].freeze

  # Attributes a profile may set.
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

  # A `<style>` block, whatever its attributes. Its contents are the profile's
  # stylesheet.
  STYLE_BLOCK = %r{<style\b[^>]*>(.*?)</style>}mi

  # What a page renders to: the cleaned markup, and the stylesheet that goes with
  # it. Kept as a pair so a caller cannot wire up one without the other.
  Rendered = Data.define(:html, :css)

  # The allowlist, with one deviation this model needs: an inline `style` goes
  # through the stylesheet policy rather than Loofah's CSS scrub, which would
  # silently drop `position` and friends — the whole point of an inline style on
  # a profile.
  class Scrubber < Rails::HTML::PermitScrubber
    def initialize
      super(prune: true)
      self.tags = TAGS
      self.attributes = ATTRIBUTES
    end

    protected
      def scrub_css_attribute(node)
        style = node.attributes["style"]
        return if style.nil?

        cleaned = PageCss.sanitize_declarations(style.value)
        cleaned.empty? ? node.remove_attribute("style") : style.value = cleaned
      end
  end

  # The scrubber, not the sanitizer, decides what survives, so the Sanitizer is
  # only a host for the parse and serialise.
  SANITIZER = Rails::HTML5::SafeListSanitizer.new

  def self.render(html)
    new(html).render
  end

  # The raw parts of a stored document, before cleaning. Used when a document is
  # rewritten — applying a layout replaces the stylesheet and keeps the markup —
  # where what is needed is the author's own text, not a cleaned rendering of it.
  def markup_source
    document.gsub(STYLE_BLOCK, "").strip
  end

  def stylesheet_source
    document.scan(STYLE_BLOCK).flatten.map(&:strip).reject(&:empty?).join("\n")
  end

  def initialize(html)
    @html = html.to_s
  end

  def render
    source = document
    Rendered.new(html: markup_of(source), css: stylesheet_of(source))
  end

  private
    # The document as parsed: valid UTF-8, within the cap. Cut to the cap, then
    # drop whatever character the cut split rather than replacing it: a
    # replacement character is three bytes, which would put the document back
    # over the cap it was just trimmed to.
    def document
      text = @html.scrub
      return "" if text.strip.empty?
      return text if text.bytesize <= MAX_BYTES

      text = text.byteslice(0, MAX_BYTES)
      text = text.byteslice(0, text.bytesize - 1) until text.empty? || text.valid_encoding?
      text
    end

    # The author's stylesheets, concatenated and cleaned as one sheet, so rules
    # in separate blocks meet the same policy and keep their order.
    def stylesheet_of(source)
      blocks = source.scan(STYLE_BLOCK).flatten
      return "" if blocks.empty?

      PageCss.sanitize(blocks.join("\n"))
    end

    # Content, cleaned. Style blocks are removed first: they are not content, and
    # the allowlist would drop them with their rules intact, which is not the same
    # thing as a stylesheet.
    def markup_of(source)
      cleaned = SANITIZER.sanitize(source.gsub(STYLE_BLOCK, ""), scrubber: Scrubber.new)
      fragment = Loofah.html5_fragment(cleaned)
      enforce_url_policy(fragment)
      mark_outbound_links(fragment)
      fragment.to_html.html_safe
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
