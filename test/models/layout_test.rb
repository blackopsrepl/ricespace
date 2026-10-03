# frozen_string_literal: true

require "test_helper"

class LayoutTest < ActiveSupport::TestCase
  test "the published layouts are readable, named and described" do
    layouts = Layout.all

    assert_operator layouts.size, :>=, 3
    layouts.each do |layout|
      assert_predicate layout.name, :present?, "#{layout.slug} has no name"
      assert_predicate layout.author, :present?, "#{layout.slug} has no author"
      assert_predicate layout.description, :present?, "#{layout.slug} has no description"
      assert_predicate layout.css, :present?, "#{layout.slug} has no css"
      # The metadata block is metadata, not stylesheet: the name line is not in the
      # rules. (A declaration mentioning a `name:` property would be, but no layout
      # sets one.)
      refute_match(/^\s*name:/, layout.css, "#{layout.slug} kept its metadata")
    end
  end

  test "every layout's css keeps every rule and declaration through the sanitiser" do
    # The sanitiser is allowed to reformat — it rebuilds rules on one line each — so
    # what is compared is what survives: every selector, and every property name.
    Layout.all.each do |layout|
      sanitized = PageCss.sanitize(layout.css)

      # A selector is what comes before the `{` on a line that opens a rule.
      selectors = layout.css.lines.filter_map do |line|
        next unless line.include?("{")

        candidate = line.split("{").first.strip
        candidate unless candidate.include?(":") || candidate.empty?
      end
      properties = layout.css.scan(/^\s*([a-z-]+)\s*:/).flatten.uniq

      selectors.each do |selector|
        assert_includes sanitized, selector, "#{layout.slug} lost the rule for #{selector}"
      end
      properties.each do |property|
        assert_includes sanitized, "#{property}:", "#{layout.slug} lost every #{property} declaration"
      end
    end
  end

  test "every layout reaches the page anatomy" do
    hooks = %w[contactTable profile-pic nametext blurb friendSpace top8 friend comment]

    Layout.all.each do |layout|
      targets = hooks.count { |hook| layout.css.include?(hook) }
      assert_operator targets, :>=, 4, "#{layout.slug} targets only #{targets} of the page's hooks"
    end
  end

  test "an unknown layout is not found" do
    assert_raises(Layout::NotFound) { Layout.find("no-such-layout") }
  end

  test "a layout is addressable by its slug" do
    assert_equal "blacklight", Layout.find("blacklight").to_param
  end
end
