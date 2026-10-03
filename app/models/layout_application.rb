# frozen_string_literal: true

# Putting a layout onto a page.
#
# A page is markup plus at most one stylesheet, and applying a layout means
# replacing that stylesheet while leaving everything the owner wrote of the page
# itself alone. Doing that with string surgery on the document is how a page ends up
# with two style blocks, one of them orphaned — so the document is taken apart into
# markup and rules, and put back together in the one shape a page is stored in:
#
#   <style>layout rules, then the page's own rules</style>
#   ...the markup the owner wrote...
class LayoutApplication
  def initialize(profile, layout)
    @profile = profile
    @layout = layout
  end

  def document
    markup = ProfileMarkup.new(@profile.document).markup_source
    [ "<style>", @layout.css, own_rules, "</style>", markup ].reject(&:blank?).join("\n")
  end

  private
    # The rules the owner had written, kept under the layout's. This is what makes
    # a layout a starting point rather than an overwrite.
    def own_rules
      ProfileMarkup.new(@profile.document).stylesheet_source.presence
    end
end
