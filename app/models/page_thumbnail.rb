# frozen_string_literal: true

# A page's thumbnail: the colours it actually wears.
#
# A directory of pages that shows a paragraph of markup per page is a list of
# filenames. What identifies a page at a glance is what it looks like, and the two
# things a thumbnail of a stylesheet can honestly show are its background and its text
# colour — read out of the page's own rules, not guessed and not a screenshot.
#
# This is a reading of the page, not a rendering of it: no browser, no image, no
# cached artefact to go stale. It reads the cleaned stylesheet, so it says what a
# visitor would get.
class PageThumbnail
  # The named colours. Listed rather than matched as "a word", because `inherit` and
  # `currentColor` are keywords and not colours, and a thumbnail that paints
  # "inherited" is worse than one that paints nothing.
  NAMED_COLOURS = %w[
    aliceblue antiquewhite aqua aquamarine azure beige bisque black blanchedalmond
    blue blueviolet brown burlywood cadetblue chartreuse chocolate coral
    cornflowerblue cornsilk crimson cyan darkblue darkcyan darkgoldenrod darkgray
    darkgreen darkgrey darkkhaki darkmagenta darkolivegreen darkorange darkorchid
    darkred darksalmon darkseagreen darkslateblue darkslategray darkslategrey
    darkturquoise darkviolet deeppink deepskyblue dimgray dimgrey dodgerblue
    firebrick floralwhite forestgreen fuchsia gainsboro ghostwhite gold goldenrod
    gray green greenyellow grey honeydew hotpink indianred indigo ivory khaki
    lavender lavenderblush lawngreen lemonchiffon lightblue lightcoral lightcyan
    lightgoldenrodyellow lightgray lightgreen lightgrey lightpink lightsalmon
    lightseagreen lightskyblue lightslategray lightslategrey lightsteelblue
    lightyellow lime limegreen linen magenta maroon mediumaquamarine mediumblue
    mediumorchid mediumpurple mediumseagreen mediumslateblue mediumspringgreen
    mediumturquoise mediumvioletred midnightblue mintcream mistyrose moccasin
    navajowhite navy oldlace olive olivedrab orange orangered orchid palegoldenrod
    palegreen paleturquoise palevioletred papayawhip peachpuff peru pink plum
    powderblue purple rebeccapurple red rosybrown royalblue saddlebrown salmon
    sandybrown seagreen seashell sienna silver skyblue slateblue slategray
    slategrey snow springgreen steelblue tan teal thistle tomato turquoise violet
    wheat white whitesmoke yellow yellowgreen
  ].to_set.freeze

  # A colour, in the forms a stylesheet says one. Everything the thumbnail draws is
  # checked against this before it reaches a style attribute, so a hostile declaration
  # cannot ride along: what comes back is a colour or nothing.
  COLOUR = /\A(?:#[0-9a-f]{3,8}|rgba?\([\d\s.,%\/]+\)|hsla?\([\d\s.,%deg\/]+\))\z|\A[a-z]{3,20}\z/i

  # Where a background is declared, in the order a page's stylesheet tends to say it.
  BACKGROUND_KEYS = %w[background-color background].freeze
  TEXT_KEYS = %w[color].freeze

  # How much of a stylesheet to read looking for them. A page's colours are at the top
  # of it, and a thumbnail is not a reason to read a 50 KB sheet on every visit to the
  # directory.
  SCAN_BYTES = 4_000

  def initialize(css)
    @css = css.to_s.byteslice(0, SCAN_BYTES)
  end

  # The page's background colour, or nil when it has not said.
  def background
    colour_for(BACKGROUND_KEYS)
  end

  # The page's text colour, or nil.
  def foreground
    colour_for(TEXT_KEYS)
  end

  # A colour to draw the thumbnail with even when the page has said nothing: the
  # site's own, so an unstyled page looks like the site rather than like a gap.
  def background_or_default
    background || "transparent"
  end

  def foreground_or_default
    foreground || "#a1a1aa"
  end

  private
    # The first colour a page declares for one of these properties. Read from a
    # declaration, never from a URL: `background: url(…)` says nothing about colour.
    def colour_for(keys)
      keys.each do |key|
        value = declarations[key]&.strip
        next if value.nil? || value.empty?

        # A background can be a shorthand with more than a colour in it, so the value
        # is tried whole first — which is what functional notation needs, since
        # `rgb(1, 2, 3)` contains spaces — and then as its first word, which is what
        # `#000 url(tile.gif) repeat` needs.
        [ value, value[/\A([^\s;]+)/, 1] ].each do |candidate|
          colour = self.class.colour(candidate)
          return colour if colour
        end
      end
      nil
    end

    # Property => first value, for the properties looked at. Deliberately shallow: it
    # does not need a CSS parser to answer "what colours does this page use", and it
    # must not fail on a stylesheet the parser would reject, because a page that fails
    # to parse still has to appear in the directory.
    def declarations
      @declarations ||= (BACKGROUND_KEYS + TEXT_KEYS).to_h do |key|
        match = @css.match(/(?:^|[{;\s])#{Regexp.escape(key)}\s*:\s*([^;}]+)/i)
        [ key, match&.[](1)&.strip ]
      end
    end

    class << self
      # A candidate value as a colour, or nil. Kept here rather than in a regex
      # constant so the named-colour list is consulted, not just a word shape: a
      # keyword like `inherit` is a word and is not a colour.
      def colour(candidate)
        return nil if candidate.nil?

        value = candidate.strip
        return nil unless value.match?(COLOUR)

        # A word is a colour only if it is one of the names.
        return value.downcase if value.match?(/\A[a-z]+\z/i) && NAMED_COLOURS.include?(value.downcase)

        value.match?(/\A[a-z]+\z/i) ? nil : value
      end
    end
end
