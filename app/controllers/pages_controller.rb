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

  # How many of a page's own colours to lift for its thumbnail, and how much of the
  # stylesheet to read looking for them.
  THUMBNAIL_COLOURS = 3
  THUMBNAIL_SCAN_BYTES = 4_000

  def home
    # `user: :profile_picture` rather than `:profile_picture`: the picture belongs to
    # the account, not to the page, and the directory draws one per page.
    @profiles = Profile.includes(user: :profile_picture).order(updated_at: :desc).limit(RECENT_PROFILES)
    @layouts = Layout.all.first(FEATURED_LAYOUTS)
    @profile_count = Profile.count
  end

  def agents
  end

  def agents_markdown
    render plain: AgentContract.markdown, content_type: "text/markdown; charset=utf-8"
  end
end
