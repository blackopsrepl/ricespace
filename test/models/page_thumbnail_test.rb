# frozen_string_literal: true

require "test_helper"

# A page's thumbnail: the colours it wears, read out of its own stylesheet.
class PageThumbnailTest < ActiveSupport::TestCase
  test "reads the page's background and text colour" do
    thumbnail = PageThumbnail.new(<<~CSS)
      body { background-color: #000000; color: #00ffff; font-family: Verdana }
      .contactTable { border: 4px ridge #00ffff }
    CSS

    assert_equal "#000000", thumbnail.background
    assert_equal "#00ffff", thumbnail.foreground
  end

  test "reads a colour written as a shorthand or a named colour" do
    assert_equal "#0f0", PageThumbnail.new("body { background: #0f0 }").background
    assert_equal "white", PageThumbnail.new("body { background-color: white }").background
    assert_equal "rgb(1, 2, 3)", PageThumbnail.new("body { background: rgb(1, 2, 3) }").background
  end

  test "a background that is only a url says nothing about colour" do
    thumbnail = PageThumbnail.new("body { background: url(https://example.com/tile.gif) repeat; color: #fff }")

    assert_nil thumbnail.background
    assert_equal "#fff", thumbnail.foreground
  end

  test "a page that has said nothing gets the site's defaults" do
    thumbnail = PageThumbnail.new("")

    assert_nil thumbnail.background
    assert_equal "transparent", thumbnail.background_or_default
    assert_equal "#a1a1aa", thumbnail.foreground_or_default
  end

  test "a value that is not a colour never becomes one" do
    # The thumbnail interpolates this into a style attribute, so whatever comes back
    # is either a colour from the vocabulary or nothing at all — never the raw text of
    # a hostile declaration. Note that `#000;} body{display:none` reads as `#000`,
    # because the extraction stops at the semicolon: that is a colour, and a safe one.
    [ "url(https://e/x.png)", "expression(alert(1))", "var(--x)", %(\\" onload=\\"alert(1)),
      "url(https://e/x.png) repeat fixed", "inherit" ].each do |hostile|
      thumbnail = PageThumbnail.new("body { background-color: #{hostile}; color: #{hostile} }")

      [ thumbnail.background, thumbnail.foreground ].each do |value|
        assert(value.nil? || PageThumbnail::COLOUR.match?(value),
          "#{hostile.inspect} produced #{value.inspect}, which is neither a colour nor nothing")
      end
      assert_nil thumbnail.background, "expected #{hostile.inspect} not to be read as a background colour"
    end
  end

  test "the shape check accepts the colour vocabulary and nothing else" do
    %w[#fff #ffffff #ffffff80 white transparent rebeccapurple rgb(1,2,3) rgba(1,2,3,.5) hsl(1,2%,3%)].each do |good|
      assert_match PageThumbnail::COLOUR, good
    end
    [ "", "url(x)", "#", "expression()", "red;}body{" ].each do |bad|
      refute_match PageThumbnail::COLOUR, bad
    end
    # A bare word matches the shape — a named colour is a bare word — so the word shape
    # alone cannot reject one. What rejects it is the name check in .colour, and that
    # is tested above: `alert` is a word, and it is not a colour.
    assert_match PageThumbnail::COLOUR, "alert"
    assert_nil PageThumbnail.colour("alert")
  end

  test "a keyword is a word but is not a colour" do
    # `inherit` and `currentColor` match the shape of a colour and are not one; a
    # thumbnail that paints "inherited" is worse than one that paints nothing.
    %w[inherit initial unset currentColor revert transparent none auto repeat fixed
      absolute hidden].each do |keyword|
      thumbnail = PageThumbnail.new("body { background-color: #{keyword}; color: #{keyword} }")

      assert_nil thumbnail.background, "expected #{keyword.inspect} not to be drawn as a background"
    end
  end

  test "a declaration in a later rule does not override the first" do
    # The first colour a page declares for its body is the one a visitor sees, and a
    # thumbnail does not need to model the cascade to be right about that.
    thumbnail = PageThumbnail.new("body { background-color: #000 } .x { background-color: #fff }")

    assert_equal "#000", thumbnail.background
  end

  test "an enormous stylesheet is read from the top only" do
    css = "body { background-color: #000 }" + ("\n/*#{"x" * 10_000}*/")

    assert_equal "#000", PageThumbnail.new(css).background
    assert_operator PageThumbnail.new(css).instance_variable_get(:@css).bytesize, :<=, 4_000
  end
end
