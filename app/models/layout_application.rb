# frozen_string_literal: true

# Putting a layout onto a page.
#
# A page is markup plus at most one stylesheet, and applying a layout means putting
# the layout's rules in and keeping the markup the owner wrote. Doing that with string
# surgery on the document is how a page ends up with two style blocks, one of them
# orphaned — so the document is taken apart into markup and rules, and put back
# together in the one shape a page is stored in:
#
#   <style>the layout's rules, then the page's own</style>
#   ...the markup the owner wrote...
#
# `keep_own_rules` decides what happens to the rules the page already had, and the two
# are genuinely different actions rather than a flag for its own sake:
#
#   * true — wearing a layout. Somebody's stylesheet is a starting point and the page's
#     own rules stay on top of it, coming last so they win, which is how the people who
#     pasted a layout in and then tweaked it expected it to behave.
#   * false — taking a layout. The copy is the point, so the page's old look goes;
#     otherwise adopting somebody's design is a no-op on any page that had styled
#     itself, and the button quietly does nothing.
class LayoutApplication
  def initialize(profile, layout, keep_own_rules: true)
    @profile = profile
    @layout = layout
    @keep_own_rules = keep_own_rules
  end

  def document
    markup = ProfileMarkup.new(@profile.document).markup_source
    [ "<style>", @layout.css, own_rules, "</style>", markup ].reject(&:blank?).join("\n")
  end

  private
    # The rules the page had, kept under the layout's when the layout is being worn and
    # dropped when it is being taken.
    def own_rules
      return nil unless @keep_own_rules

      ProfileMarkup.new(@profile.document).stylesheet_source.presence
    end
end
