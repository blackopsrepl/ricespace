# frozen_string_literal: true

# The front page: a directory of pages, and the layouts people are wearing.
#
# A directory rather than a feed, and ordered by change rather than by a score,
# because there is no score here — the point of the site is that the page is the page
# and nothing ranks it. What the front page is for is finding somebody's page to look
# at, which means showing a page rather than describing it.
class PagesController < ApplicationController
  RECENT_PROFILES = 12
  FEATURED_LAYOUTS = 3

  # The gallery of rices on the front page. More than this and the front page becomes a
  # scroll rather than a table of contents.
  SHOWCASES_SHOWN = 8

  # How many of a page's own colours to lift for its thumbnail, and how much of the
  # stylesheet to read looking for them.
  THUMBNAIL_COLOURS = 3
  THUMBNAIL_SCAN_BYTES = 4_000

  def home
    # The rices first, because a rice is the thing worth looking at: `joins(:shots)` so
    # only showcases that actually have a picture are considered, then `cover` picks the
    # first attached one. Ordered by change rather than by a score — nothing here ranks.
    @showcases = Showcase.includes(:user, shots: { image_attachment: :blob })
      .joins(:shots).distinct.order(updated_at: :desc).limit(SHOWCASES_SHOWN * 3)
      .select(&:cover).first(SHOWCASES_SHOWN)

    # `user: :profile_picture` rather than `:profile_picture`: the picture belongs to
    # the account, not to the page, and the directory draws one per page.
    @profiles = Profile.includes(user: :profile_picture).order(updated_at: :desc).limit(RECENT_PROFILES)
    @layouts = Layout.all.first(FEATURED_LAYOUTS)
    @profile_count = Profile.count
    @showcase_count = Showcase.count
  end

  def agents
  end

  def agents_markdown
    render plain: AgentContract.markdown, content_type: "text/markdown; charset=utf-8"
  end
end
