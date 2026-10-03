# frozen_string_literal: true

require "test_helper"

class ProfileMarkupTest < ActiveSupport::TestCase
  test "keeps the presentational vocabulary profiles are built with" do
    html = render(<<~HTML).html
      <h1>Vittorio</h1>
      <marquee behavior="alternate" scrollamount="3">
        <font color="#ff00ff" face="Comic Sans MS">welcome to my page</font>
      </marquee>
      <img src="https://example.com/avatar.gif" width="120" height="90" alt="me">
      <table border="1" cellpadding="4"><tr><td bgcolor="#000000">guestbook</td></tr></table>
      <p class="blink">under construction</p>
    HTML

    %w[<marquee <font <img <table <td <h1].each do |tag|
      assert_includes html, tag
    end
    assert_includes html, %(face="Comic Sans MS")
    assert_includes html, %(bgcolor="#000000")
  end

  test "a stylesheet is kept as a stylesheet, and can lay the whole page out" do
    rendered = render(<<~HTML)
      <style>
        body { background: #333 url(https://example.com/tile.gif) fixed; }
        .main { position: absolute; left: 50%; top: 130px; margin-left: -400px; z-index: 3; }
        .orangetext15 { visibility: hidden; }
        td.text td.text table .btext { display: none !important; }
      </style>
      <div class="main">hi</div>
    HTML

    # Not in the markup: a stylesheet is not content.
    refute_includes rendered.html, "<style"

    assert_includes rendered.css, "background: #333 url(https://example.com/tile.gif) fixed"
    assert_includes rendered.css, "position: absolute"
    assert_includes rendered.css, "z-index: 3"
    assert_includes rendered.css, "margin-left: -400px"
    assert_includes rendered.css, "visibility: hidden"
    assert_includes rendered.css, "display: none !important"
    assert_includes rendered.css, "td.text td.text table .btext"
    assert_includes rendered.html, %(<div class="main">hi</div>)
  end

  test "several style blocks are one sheet and keep their order" do
    rendered = render(<<~HTML)
      <style>.a { color: red }</style>
      <p>between</p>
      <style>.b { color: blue }</style>
    HTML

    assert_includes rendered.css, ".a { color: red; }"
    assert_includes rendered.css, ".b { color: blue; }"
    assert_operator rendered.css.index(".a "), :<, rendered.css.index(".b ")
  end

  test "a stylesheet cannot fetch what the author may not fetch" do
    rendered = render(<<~HTML)
      <style>
        @import url(https://evil.example/x.css);
        .a { background: url(javascript:alert(1)); }
        .b { background: url(https://example.com/ok.png); }
      </style>
    HTML

    refute_includes rendered.css, "@import"
    refute_includes rendered.css, "evil.example"
    refute_includes rendered.css, "javascript:"
    assert_includes rendered.css, "url(https://example.com/ok.png)"
  end

  test "an inline style keeps its position, because that is what it is for" do
    html = render(%(<div style="position:absolute;top:0;left:0;z-index:9999;color:red">x</div>)).html

    assert_includes html, "position: absolute"
    assert_includes html, "z-index: 9999"
    assert_includes html, "color: red"
  end

  test "an inline style cannot fetch a url the author may not fetch" do
    html = render(%(<div style="background:url(javascript:alert(1));color:red">x</div>)).html

    refute_includes html, "javascript:"
    assert_includes html, "color: red"
  end

  test "removes scripts with their contents" do
    html = render(%(<p>before</p><script>alert("pwned")</script><p>after</p>)).html

    assert_includes html, "<p>before</p>"
    assert_includes html, "<p>after</p>"
    refute_includes html, "script"
    refute_includes html, "pwned"
  end

  test "a script hidden inside a style block is still not content" do
    rendered = render(%(<style>.a { color: red }</style><script>alert("pwned")</script>))

    refute_includes rendered.html, "pwned"
    assert_includes rendered.css, "color: red"
  end

  test "removes inline event handlers" do
    html = render(<<~HTML).html
      <img src="/avatar.png" onerror="alert(1)" onload="alert(2)">
      <p onclick="alert(3)" onmouseover="alert(4)">hover</p>
    HTML

    refute_includes html, "onerror"
    refute_includes html, "onload"
    refute_includes html, "onclick"
    refute_includes html, "onmouseover"
    assert_includes html, %(src="/avatar.png")
  end

  test "removes elements that navigate, embed or execute" do
    html = render(<<~HTML).html
      <iframe src="https://example.com"></iframe>
      <object data="https://example.com"></object>
      <embed src="https://example.com">
      <form action="/logout"><input name="x"><button>go</button></form>
      <meta http-equiv="refresh" content="0;url=https://example.com">
      <base href="https://example.com">
      <link rel="stylesheet" href="https://example.com/x.css">
      <svg><script>alert(1)</script></svg>
    HTML

    %w[<iframe <object <embed <form <input <button <meta <base <link <svg].each do |tag|
      refute_includes html, tag
    end
  end

  test "keeps links and images on allowed URLs and drops the rest" do
    html = render(<<~HTML).html
      <a href="https://example.com/article">open web</a>
      <a href="/profiles/2">another profile</a>
      <a href="#top">anchor</a>
      <a href="mailto:me@example.com">mail</a>
      <a href="javascript:alert(1)">bad</a>
      <a href="data:text/html;base64,PHNjcmlwdD4=">bad</a>
      <img src="https://example.com/a.gif">
      <img src="data:image/svg+xml;base64,PHN2Zz4=">
      <img src="javascript:alert(1)">
    HTML

    assert_includes html, %(href="https://example.com/article")
    assert_includes html, %(href="/profiles/2")
    assert_includes html, %(href="#top")
    assert_includes html, %(href="mailto:me@example.com")
    assert_includes html, %(src="https://example.com/a.gif")
    refute_includes html, "javascript:"
    refute_includes html, "data:"
  end

  test "marks links as author-contributed" do
    html = render(%(<a href="https://example.com">c</a><a href="/x">i</a>)).html

    assert_equal 2, html.scan(%(rel="nofollow ugc noopener")).size
  end

  test "reports comments and doctypes as nothing to render" do
    html = render("<!-- secret --><!doctype html><p>text</p>").html

    refute_includes html, "secret"
    refute_includes html, "doctype"
    assert_includes html, "<p>text</p>"
  end

  test "an empty page is empty markup and an empty stylesheet" do
    [ nil, "", "   " ].each do |blank|
      rendered = ProfileMarkup.render(blank)

      assert_equal "", rendered.html.to_s
      assert_equal "", rendered.css
    end
  end

  test "returns markup that templates can interpolate" do
    assert_predicate ProfileMarkup.render("<p>x</p>").html, :html_safe?
  end

  test "caps runaway documents instead of parsing them" do
    source = %(<p>#{"a" * ProfileMarkup::MAX_BYTES}</p><p>BEYOND-CAP-MARKER</p>)

    html = render(source).html

    refute_includes html, "BEYOND-CAP-MARKER"
    # The cap bounds the document handed to the parser, so the render can exceed
    # it by only the closing tags the serializer restores.
    assert_operator html.bytesize, :<, ProfileMarkup::MAX_BYTES + 1_000
  end

  test "survives invalid encoding in stored markup" do
    rendered = ProfileMarkup.render("<p>\xff\xfe bytes</p>").html

    assert_includes rendered, "bytes"
    assert_predicate rendered, :valid_encoding?
  end

  private
    def render(html)
      ProfileMarkup.render(html)
    end
end
