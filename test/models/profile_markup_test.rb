# frozen_string_literal: true

require "test_helper"

class ProfileMarkupTest < ActiveSupport::TestCase
  test "keeps the presentational vocabulary profiles are built with" do
    rendered = render(<<~HTML)
      <h1>Vittorio</h1>
      <marquee behavior="alternate" scrollamount="3">
        <font color="#ff00ff" face="Comic Sans MS">welcome to my page</font>
      </marquee>
      <img src="https://example.com/avatar.gif" width="120" height="90" alt="me">
      <table border="1" cellpadding="4"><tr><td bgcolor="#000000">guestbook</td></tr></table>
      <p class="blink">under construction</p>
    HTML

    %w[<marquee <font <img <table <td <h1].each do |tag|
      assert_includes rendered, tag
    end
    assert_includes rendered, %(face="Comic Sans MS")
    assert_includes rendered, %(bgcolor="#000000")
  end

  test "keeps inline style but strips declarations that escape the profile" do
    rendered = render(%(<div style="position:fixed;top:0;left:0;z-index:9999;color:red">x</div>))

    assert_includes rendered, "color:red"
    refute_includes rendered, "position:fixed"
    refute_includes rendered, "z-index"
  end

  test "removes scripts with their contents" do
    rendered = render(%(<p>before</p><script>alert("pwned")</script><p>after</p>))

    assert_includes rendered, "<p>before</p>"
    assert_includes rendered, "<p>after</p>"
    refute_includes rendered, "script"
    refute_includes rendered, "pwned"
  end

  test "removes inline event handlers" do
    rendered = render(<<~HTML)
      <img src="/avatar.png" onerror="alert(1)" onload="alert(2)">
      <p onclick="alert(3)" onmouseover="alert(4)">hover</p>
    HTML

    refute_includes rendered, "onerror"
    refute_includes rendered, "onload"
    refute_includes rendered, "onclick"
    refute_includes rendered, "onmouseover"
    assert_includes rendered, %(src="/avatar.png")
  end

  test "removes elements that navigate, embed or restyle the page" do
    rendered = render(<<~HTML)
      <style>body { display: none }</style>
      <iframe src="https://example.com"></iframe>
      <object data="https://example.com"></object>
      <embed src="https://example.com">
      <form action="/logout"><input name="x"><button>go</button></form>
      <meta http-equiv="refresh" content="0;url=https://example.com">
      <base href="https://example.com">
      <link rel="stylesheet" href="https://example.com/x.css">
      <svg><script>alert(1)</script></svg>
    HTML

    %w[<style <iframe <object <embed <form <input <button <meta <base <link <svg].each do |tag|
      refute_includes rendered, tag
    end
    refute_includes rendered, "display: none"
  end

  test "keeps links and images on allowed URLs and drops the rest" do
    rendered = render(<<~HTML)
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

    assert_includes rendered, %(href="https://example.com/article")
    assert_includes rendered, %(href="/profiles/2")
    assert_includes rendered, %(href="#top")
    assert_includes rendered, %(href="mailto:me@example.com")
    assert_includes rendered, %(src="https://example.com/a.gif")
    refute_includes rendered, "javascript:"
    refute_includes rendered, "data:"
  end

  test "marks links as author-contributed" do
    rendered = render(%(<a href="https://example.com">c</a><a href="/x">i</a>))

    assert_equal 2, rendered.scan(%(rel="nofollow ugc noopener")).size
  end

  test "reports comments and doctypes as nothing to render" do
    rendered = render("<!-- secret --><!doctype html><p>text</p>")

    refute_includes rendered, "secret"
    refute_includes rendered, "doctype"
    assert_includes rendered, "<p>text</p>"
  end

  test "returns an empty safe string for blank markup" do
    assert_equal "", ProfileMarkup.render(nil).to_s
    assert_equal "", ProfileMarkup.render("").to_s
    assert_equal "", ProfileMarkup.render("   ").to_s
  end

  test "returns markup that templates can interpolate" do
    assert_predicate ProfileMarkup.render("<p>x</p>"), :html_safe?
  end

  test "caps runaway documents instead of parsing them" do
    html = %(<p>#{"a" * ProfileMarkup::MAX_BYTES}</p><p>BEYOND-CAP-MARKER</p>)

    rendered = render(html)

    refute_includes rendered, "BEYOND-CAP-MARKER"
    # The cap bounds the document handed to the parser, so the render can exceed
    # it by only the closing tags the serializer restores.
    assert_operator rendered.bytesize, :<, ProfileMarkup::MAX_BYTES + 1_000
  end

  test "survives invalid encoding in stored markup" do
    rendered = ProfileMarkup.render("<p>\xff\xfe bytes</p>").to_s

    assert_includes rendered, "bytes"
    assert_predicate rendered, :valid_encoding?
  end

  private
    def render(html)
      ProfileMarkup.render(html).to_s
    end
end
