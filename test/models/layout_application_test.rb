# frozen_string_literal: true

require "test_helper"

# Applying a layout: what is replaced, what is kept, and what the page is after.
class LayoutApplicationTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(username: "vittorio", email_address: "v@example.com", password: "correct horse battery")
    @profile = @user.profile
    @layout = Layout.find("blacklight")
  end

  test "applying a layout puts its rules on the page and keeps the page's markup" do
    @profile.update!(document: %(<style>.mine { color: red }</style><marquee>my page</marquee>))

    @profile.update!(document: LayoutApplication.new(@profile, @layout).document)
    rendered = @profile.rendered

    assert_includes @profile.document, "<marquee>my page</marquee>"
    assert_includes rendered.css, "background-color: #000000"
    assert_includes rendered.html, "<marquee>my page</marquee>"
  end

  test "wearing a layout keeps the page's own rules under it, so they win" do
    @profile.update!(document: %(<style>.mine { color: red }</style><p>hi</p>))
    @profile.update!(document: LayoutApplication.new(@profile, @layout).document)
    css = @profile.rendered.css

    assert_includes css, ".mine"
    assert_operator css.index(@layout.css.lines.first.strip), :<, css.index(".mine"),
      "the page's own rules should come after the layout's"
  end

  test "taking a layout drops the page's own rules" do
    @profile.update!(document: %(<style>.mine { color: red }</style><p>hi</p>))
    @profile.update!(document: LayoutApplication.new(@profile, @layout, keep_own_rules: false).document)
    css = @profile.rendered.css

    refute_includes css, ".mine"
    assert_includes css, "background-color: #000000"
    assert_includes @profile.document, "<p>hi</p>", "the markup is not a rule and stays"
  end

  test "a page has one stylesheet after applying, not two" do
    @profile.update!(document: %(<style>.mine { color: red }</style><p>hi</p>))
    @profile.update!(document: LayoutApplication.new(@profile, @layout).document)

    assert_equal 1, @profile.document.scan(/<style\b/i).size
    # Each of the layout's rules appears once on the page's sheet, not twice.
    assert_equal 1, @profile.rendered.css.scan(/\.contactTable\s*\{/).size
    assert_equal 1, @profile.rendered.css.scan(/\.blurb\s*\{/).size
  end

  test "applying a layout twice does not stack it" do
    @profile.update!(document: LayoutApplication.new(@profile, @layout).document)
    @profile.update!(document: LayoutApplication.new(@profile, @layout).document)

    assert_equal 1, @profile.document.scan(/<style\b/i).size
  end

  test "applying a layout to an empty page gives the page a stylesheet and nothing else" do
    @profile.update!(document: LayoutApplication.new(@profile, @layout).document)

    assert_includes @profile.rendered.css, "background-color: #000000"
    assert_equal "<style>\n#{@layout.css}\n</style>", @profile.document
  end
end
