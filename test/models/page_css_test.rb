# frozen_string_literal: true

require "test_helper"

# A profile's stylesheet is the page's look. These tests are what the sanitiser
# must keep and what it must drop, written from the layouts the era was built
# from: absolutely positioned wrappers, hidden site chrome, table-nesting
# selectors, `!important` fights.
class PageCssTest < ActiveSupport::TestCase
  test "keeps the vocabulary profiles lay themselves out with" do
    css = PageCss.sanitize(<<~CSS)
      body { background: #333 url(https://example.com/tile.gif) repeat fixed; color: white; }
      .main { position: absolute; left: 50%; top: 130px; width: 800px; height: 1300px; margin-left: -400px; z-index: 3; }
      .orangetext15 { visibility: hidden; }
      td.text td.text table .btext { display: none !important; }
      * { cursor: url(https://example.com/cursor.cur), auto; }
    CSS

    assert_includes css, "position: absolute"
    assert_includes css, "z-index: 3"
    assert_includes css, "margin-left: -400px"
    assert_includes css, "visibility: hidden"
    assert_includes css, "display: none !important"
    assert_includes css, "td.text td.text table .btext"
    assert_includes css, "*"
    assert_includes css, "url(https://example.com/tile.gif)"
    assert_includes css, "url(https://example.com/cursor.cur)"
  end

  test "drops declarations whose url is not a fetch the author may make" do
    css = PageCss.sanitize(<<~CSS)
      .a { background: url(javascript:alert(1)); }
      .b { background: url(data:image/svg+xml;base64,PHN2Zz4=); }
      .c { background: url(https://example.com/ok.png); color: red; }
    CSS

    refute_includes css, "javascript:"
    refute_includes css, "data:"
    assert_includes css, "url(https://example.com/ok.png)"
    # The refused declaration goes, not just its URL.
    refute_includes css, ".a {"
    refute_includes css, ".b {"
  end

  test "drops declarations that are a scripting mechanism in some engine" do
    css = PageCss.sanitize(<<~CSS)
      .x { width: expression(alert(1)); color: red; }
      .y { behavior: url(#default#time2); color: red; }
      .z { -moz-binding: url(https://example.com/x.xml); color: red; }
    CSS

    refute_includes css, "expression"
    refute_includes css, "behavior"
    refute_includes css, "-moz-binding"
    assert_equal 3, css.scan("color: red").size
  end

  test "drops at-rules, which can fetch or re-declare a document" do
    css = PageCss.sanitize(<<~CSS)
      @import url(https://evil.example/x.css);
      @media print { body { display: none } }
      .kept { color: red; }
    CSS

    refute_includes css, "@import"
    refute_includes css, "@media"
    refute_includes css, "evil.example"
    assert_includes css, ".kept { color: red; }"
  end

  test "strips comments" do
    css = PageCss.sanitize(".a { color: red; /* hide the ad */ } .b /* x */ { color: blue; }")

    refute_includes css, "hide the ad"
    assert_includes css, "color: red"
    assert_includes css, "color: blue"
  end

  test "an unclosed rule cannot leak into the rest of the sheet" do
    css = PageCss.sanitize(".a { color: red; } } body { display: none }")

    assert_includes css, "color: red"
    refute_includes css, "display: none"
  end

  test "a declaration cannot close the style element it is written into" do
    css = PageCss.sanitize('.a { content: "</style><script>alert(1)</script>"; color: red; }')

    refute_includes css, "<"
    refute_includes css, "script"
    assert_includes css, "color: red"

    assert_equal "", PageCss.sanitize_declarations(%(content: "</style><img src=x onerror=alert(1)>"))
  end

  test "inline styles and stylesheets follow the same policy" do
    assert_equal "position: fixed; z-index: 9; color: red;",
      PageCss.sanitize_declarations("position:fixed; z-index:9; color: red")
    assert_equal "", PageCss.sanitize_declarations("background: url(javascript:alert(1))")
    assert_equal "background: url(https://example.com/a.png);",
      PageCss.sanitize_declarations("background: url(https://example.com/a.png)")
  end

  test "blank and oversized stylesheets are dealt with rather than parsed" do
    assert_equal "", PageCss.sanitize(nil)
    assert_equal "", PageCss.sanitize("   ")
    assert_equal "", PageCss.sanitize_declarations("\xff\xfe")

    css = PageCss.sanitize(".a { color: red; }\n/*#{"x" * (PageCss::MAX_BYTES + 1_000)}*/")
    assert_operator css.bytesize, :<, PageCss::MAX_BYTES + 1_000
  end
end
