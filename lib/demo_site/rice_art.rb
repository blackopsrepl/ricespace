# frozen_string_literal: true

require "vips"

module DemoSite
  # Draw the demo rices: one desktop, per account, in that account's theme.
  #
  # A rice is a screenshot of somebody's setup, and it is the reason the site exists — the
  # first thing a visitor looks at. A demo build has no desktops to photograph, so these are
  # drawn, and drawn honestly: the picture shows the window manager, the bar, the terminal, the
  # font and the theme the page's own facts claim. A picture that is wrong in an obvious way (a
  # real desktop belonging to nobody) would be worse than an honest diagram.
  #
  # Everything is drawn in RGBA and flattened once at the end, because vips composites with
  # "over" only on an image that has an alpha channel: text arrives as a one-band coverage
  # mask, and laying it down needs somewhere for the un-inked part to be transparent.
  #
  # Nothing here touches the network or the database — it takes a theme and returns PNG bytes.
  module RiceArt
    WIDTH = 1600
    HEIGHT = 900
    PAD = 40
    BAR = 30
    GAP = 10

    # Vips sizes text in points at a DPI, not in pixels. 96 gives roughly the size a terminal
    # actually is at this scale.
    DPI = 96
    LINE = 24
    TEXT_SIZE = 14

    MONO = "Liberation Mono, DejaVu Sans Mono, monospace"

    # A theme: the wallpaper's two colours, an accent, and the clock. The names are the shipped
    # layouts' names, so a page wearing Tokyo Night gets a Tokyo Night desktop.
    THEMES = {
      "tokyo-night" => {
        bg: [ 26, 27, 38 ], bg2: [ 20, 21, 30 ], fg: [ 192, 202, 245 ], dim: [ 86, 95, 137 ],
        accent: [ 122, 162, 247 ], green: [ 158, 206, 106 ], yellow: [ 224, 175, 104 ],
        window: [ 36, 40, 59 ], clock: "00:42"
      },
      "catppuccin" => {
        bg: [ 30, 30, 46 ], bg2: [ 22, 22, 34 ], fg: [ 205, 214, 244 ], dim: [ 108, 112, 134 ],
        accent: [ 137, 180, 250 ], green: [ 166, 227, 161 ], yellow: [ 249, 226, 175 ],
        window: [ 49, 50, 68 ], clock: "23:58"
      },
      "gruvbox" => {
        bg: [ 40, 40, 40 ], bg2: [ 26, 28, 29 ], fg: [ 235, 219, 178 ], dim: [ 146, 131, 116 ],
        accent: [ 131, 165, 152 ], green: [ 184, 187, 38 ], yellow: [ 250, 189, 47 ],
        window: [ 60, 56, 54 ], clock: "01:13"
      },
      "everforest" => {
        bg: [ 45, 53, 59 ], bg2: [ 34, 40, 45 ], fg: [ 211, 198, 170 ], dim: [ 133, 146, 137 ],
        accent: [ 167, 192, 128 ], green: [ 167, 192, 128 ], yellow: [ 219, 188, 127 ],
        window: [ 52, 63, 68 ], clock: "02:04"
      },
      "lumon" => {
        bg: [ 22, 28, 34 ], bg2: [ 14, 18, 23 ], fg: [ 214, 226, 233 ], dim: [ 108, 126, 138 ],
        accent: [ 126, 200, 227 ], green: [ 138, 214, 170 ], yellow: [ 226, 209, 138 ],
        window: [ 31, 42, 50 ], clock: "09:15"
      },
      "ethereal" => {
        bg: [ 38, 30, 51 ], bg2: [ 25, 19, 34 ], fg: [ 226, 214, 240 ], dim: [ 138, 118, 160 ],
        accent: [ 199, 146, 234 ], green: [ 158, 206, 168 ], yellow: [ 231, 194, 148 ],
        window: [ 50, 40, 66 ], clock: "03:33"
      },
      "miasma" => {
        bg: [ 34, 34, 34 ], bg2: [ 23, 23, 23 ], fg: [ 200, 195, 185 ], dim: [ 122, 118, 110 ],
        accent: [ 148, 160, 108 ], green: [ 148, 160, 108 ], yellow: [ 190, 170, 120 ],
        window: [ 44, 44, 42 ], clock: "04:17"
      },
      "hackerman" => {
        bg: [ 5, 12, 8 ], bg2: [ 2, 7, 4 ], fg: [ 106, 255, 140 ], dim: [ 52, 130, 74 ],
        accent: [ 106, 255, 140 ], green: [ 106, 255, 140 ], yellow: [ 190, 255, 120 ],
        window: [ 8, 20, 12 ], clock: "13:37"
      },
      "blacklight" => {
        bg: [ 22, 18, 30 ], bg2: [ 13, 10, 19 ], fg: [ 226, 220, 240 ], dim: [ 118, 108, 140 ],
        accent: [ 180, 140, 255 ], green: [ 140, 220, 180 ], yellow: [ 240, 200, 140 ],
        window: [ 32, 26, 44 ], clock: "22:30"
      },
      "newspaper" => {
        bg: [ 238, 232, 218 ], bg2: [ 224, 217, 200 ], fg: [ 40, 36, 30 ], dim: [ 120, 112, 100 ],
        accent: [ 138, 60, 40 ], green: [ 70, 100, 70 ], yellow: [ 150, 120, 40 ],
        window: [ 246, 242, 232 ], clock: "07:40"
      },
      "terminal" => {
        bg: [ 8, 10, 8 ], bg2: [ 3, 5, 3 ], fg: [ 210, 230, 200 ], dim: [ 100, 120, 100 ],
        accent: [ 140, 220, 140 ], green: [ 140, 220, 140 ], yellow: [ 210, 210, 130 ],
        window: [ 12, 16, 12 ], clock: "05:05"
      },
      "default" => {
        bg: [ 24, 24, 27 ], bg2: [ 16, 16, 19 ], fg: [ 228, 228, 231 ], dim: [ 130, 130, 140 ],
        accent: [ 250, 189, 47 ], green: [ 160, 210, 140 ], yellow: [ 250, 189, 47 ],
        window: [ 39, 39, 42 ], clock: "11:11"
      }
    }.freeze

    module_function

    # PNG bytes for one account's desktop.
    def draw(theme:, name:, facts: {})
      colours = THEMES[theme.to_s] || THEMES["default"]
      canvas = wall(colours)
      canvas = bar(canvas, colours, facts, name)

      left = (WIDTH * 0.54).round
      top = PAD + BAR + GAP
      height = HEIGHT - top - PAD
      right_x = PAD + left + GAP
      right_w = WIDTH - PAD - right_x

      canvas = editor(canvas, colours, PAD, top, left, height, name, facts)
      canvas = terminal(canvas, colours, right_x, top, right_w, height, facts)

      # Three bands and 8-bit is what a screenshot is. Nothing has been drawn at less than
      # full opacity — every rectangle and every glyph goes down opaque over an opaque
      # wallpaper — so the alpha is dropped rather than flattened, which also sidesteps
      # `flatten` wanting a background sized to a band count the canvas does not have.
      canvas.extract_band(0, n: 3).cast("uchar").write_to_buffer(".png")
    end

    # The wallpaper: the theme's two colours as a vertical gradient, with a faint grid. A flat
    # fill reads as a placeholder; this reads as a desktop.
    def wall(colours)
      height = HEIGHT
      width = WIDTH
      ramp = Vips::Image.xyz(width, height).extract_band(1).linear(1.0 / height, 0)
      bands = 3.times.map do |i|
        ramp.linear((colours[:bg][i] - colours[:bg2][i]).to_f, colours[:bg2][i])
      end
      base = Vips::Image.bandjoin(bands)

      grid = Vips::Image.black(width, height)
      (0...width).step(80) { |x| grid = grid.draw_rect(8, x, 0, 1, height) }
      (0...height).step(80) { |y| grid = grid.draw_rect(8, 0, y, width, 1) }

      # Exactly four bands, taken band by band rather than trusted from the arithmetic: the
      # canvas is RGBA for the rest of the drawing, and a step that returns one band too many
      # makes every later composite fail on a band mismatch.
      lit = base.composite(grid.bandjoin(grid.bandjoin(grid)), "add").cast("uchar")
      alpha = Vips::Image.black(width, height).new_from_image(255)

      Vips::Image.bandjoin([
        lit.extract_band(0), lit.extract_band(1), lit.extract_band(2), alpha
      ]).copy(interpretation: "srgb")
    end

    # The bar: tags with the focused one filled, the machine's name, the window manager, the
    # bar, the clock, the battery. What a bar actually carries.
    def bar(canvas, colours, facts, name)
      canvas = rect(canvas, colours[:bg2], 0, 0, WIDTH, PAD + BAR)
      canvas = rect(canvas, colours[:window], PAD, PAD, WIDTH - (PAD * 2), BAR)
      canvas = bar_right(canvas, colours, facts)

      x = PAD + 16
      %w[1 2 3 4 5].each_with_index do |tag, i|
        on = i.zero?
        canvas = rect(canvas, on ? colours[:accent] : colours[:dim], x, PAD + 8, 24, BAR - 16)
        canvas = text(canvas, tag, x + 8, PAD + 9, on ? colours[:bg2] : colours[:fg])
        x += 32
      end

      wm = (facts[:wm] || "sway").to_s.split.first.to_s
      canvas = text(canvas, name.to_s, PAD + 230, PAD + 9, colours[:fg])
      # The window manager sits at its own column, not after an estimated pen advance: at a
      # guessed 8px a character the name and the window manager ran into each other.
      text(canvas, wm, PAD + 330, PAD + 9, colours[:dim])
      canvas
    end

    # What the bar says on the right: the bar's own name, the time, the battery.
    def bar_right(canvas, colours, facts)
      right = "#{facts[:bar]}   #{colours[:clock]}   ▮▮▯"
      text(canvas, right, WIDTH - PAD - (right.length * 9) - 20, PAD + 9, colours[:fg])
    end

    # A tiling editor: the filename, line numbers, a few lines of a stylesheet. Syntax colour
    # is most of what makes a screenshot read as a desktop rather than a diagram.
    def editor(canvas, colours, x, y, width, height, name, facts)
      canvas = panel(canvas, colours, x, y, width, height, "#{name}.css")

      lines = [
        [ ":root {", colours[:accent] ],
        [ "  --bg:     ##{hex(colours[:bg2])};", colours[:fg] ],
        [ "  --fg:     ##{hex(colours[:fg])};", colours[:fg] ],
        [ "  --accent: ##{hex(colours[:accent])};", colours[:green] ],
        [ "}", colours[:accent] ],
        [ "", colours[:fg] ],
        [ "body {", colours[:accent] ],
        [ "  background: var(--bg);", colours[:fg] ],
        [ "  color: var(--fg);", colours[:fg] ],
        [ "  font: \"#{facts[:font] || "monospace"}\";", colours[:yellow] ],
        [ "}", colours[:accent] ],
        [ "", colours[:fg] ],
        [ ".rice-frame {", colours[:accent] ],
        [ "  border: 2px solid var(--accent);", colours[:fg] ],
        [ "}", colours[:accent] ]
      ]

      ty = y + 48
      lines.each_with_index do |(line, colour), i|
        break if ty > y + height - 34

        canvas = text(canvas, (i + 1).to_s.rjust(3), x + 18, ty, colours[:dim])
        canvas = text(canvas, line, x + 64, ty, colour)
        ty += LINE
      end

      # The cursor, on the line it would be on.
      rect(canvas, colours[:accent], x + 64, ty - LINE, 8, 18)
    end

    # A terminal running the box's own fetch: host, window manager, bar, terminal, font, theme
    # — the same facts the page lists beside the picture, which is the point of it.
    #
    # The label and the value are placed at fixed columns rather than run together, because
    # advancing a pen by an estimated character width drifts and eventually collides: "wm" and
    # its value ended up touching when the guess was a pixel out per character.
    def terminal(canvas, colours, x, y, width, height, facts)
      canvas = panel(canvas, colours, x, y, width, height, "#{facts[:term] || "foot"}")

      label_x = x + 22
      value_x = x + 100
      rows = [
        [ "os", "arch linux" ],
        [ "wm", facts[:wm] ],
        [ "bar", facts[:bar] ],
        [ "term", facts[:term] ],
        [ "font", facts[:font] ],
        [ "theme", facts[:theme] ],
        [ "shell", "zsh" ],
        [ "up", "3 days, 4 hours" ]
      ]

      ty = y + 48
      canvas = text(canvas, "you", x + 22, ty, colours[:accent])
      canvas = text(canvas, "@", x + 22 + 24, ty, colours[:dim])
      canvas = text(canvas, facts[:host] || "ricebox", x + 22 + 34, ty, colours[:green])
      ty += LINE
      canvas = text(canvas, "─" * 22, x + 22, ty, colours[:dim])
      ty += LINE

      rows.each do |(label, value)|
        break if ty > y + height - 34

        canvas = text(canvas, label, label_x, ty, colours[:accent])
        canvas = text(canvas, value.to_s, value_x, ty, colours[:fg])
        ty += LINE
      end

      ty += LINE
      [ "ls", "" ].each do |command|
        break if ty > y + height - 34

        canvas = text(canvas, "~/rice", x + 22, ty, colours[:green])
        canvas = text(canvas, "❯", x + 22 + 66, ty, colours[:dim])
        canvas = text(canvas, command, x + 22 + 84, ty, colours[:fg])
        ty += LINE
      end
      canvas = text(canvas, "page.html  rice.json  assets/", x + 22, ty, colours[:fg])
      ty += LINE
      canvas = text(canvas, "~/rice", x + 22, ty, colours[:green])
      canvas = text(canvas, "❯", x + 22 + 66, ty, colours[:dim])
      rect(canvas, colours[:accent], x + 22 + 84, ty - 3, 8, 18)
    end

    # A window: a title strip, then the body.
    def panel(canvas, colours, x, y, width, height, title)
      canvas = rect(canvas, colours[:window], x, y, width, height)
      canvas = rect(canvas, colours[:accent], x, y, width, 2)
      canvas = rect(canvas, colours[:bg2], x, y + 2, width, 26)
      text(canvas, title.to_s, x + 12, y + 7, colours[:dim])
    end

    # One run of text.
    #
    # Vips returns text as a one-band coverage mask, so it is colourised, given that mask as
    # its alpha, and laid over the canvas. The offset is an array because composite takes a
    # position per input image — the canvas sits at 0,0 and the text where it goes.
    def text(canvas, string, x, y, colour)
      string = string.to_s
      return canvas if string.strip.empty?

      mask = Vips::Image.text(string, font: MONO, dpi: DPI)
      return canvas if mask.width.zero? || mask.height.zero?

      ink = Vips::Image.black(mask.width, mask.height, bands: 3).new_from_image(colour)
      overlay = ink.bandjoin(mask).copy(interpretation: "srgb")
      canvas.composite(overlay, "over", x: [ x ], y: [ y ])
    rescue Vips::Error => e
      # A missing font or an unblendable canvas used to return silently, which draws a desktop
      # with no writing on it and looks like a layout bug rather than a failure.
      warn "rice_art: could not draw #{string.inspect}: #{e.message}"
      canvas
    end

    # A solid rectangle in one of the theme's colours.
    #
    # `draw_rect` paints one band, so the canvas is split, the colour is drawn into each of its
    # three, and they are joined again; the fourth band is the alpha and is left alone.
    def rect(canvas, colour, x, y, width, height)
      bands = canvas.bandsplit.each_with_index.map do |band, i|
        colour[i] ? band.draw_rect(colour[i], x, y, width, height) : band
      end
      # Joining bands drops the interpretation, and `composite` needs it to be srgb — without
      # this every text laid down after the first rectangle quietly failed to draw.
      Vips::Image.bandjoin(bands).copy(interpretation: "srgb")
    end

    def hex(rgb)
      rgb.map { |c| c.to_s(16).rjust(2, "0") }.join
    end
  end
end
