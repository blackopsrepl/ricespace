# frozen_string_literal: true

# The front page: the pages people made, and what other people thought of them.
#
# Still a directory rather than a feed. There is no stream, no "for you", and nothing
# arrives on this page on its own — what there is, now, is a score, because a page you
# can rate is a page worth being told about. Popularity here is the old kind: a count of
# people who said they liked somebody's page, shown next to the page itself.
class PagesController < ApplicationController
  RECENT_PROFILES = 12
  FEATURED_LAYOUTS = 3

  # The gallery of rices on the front page. More than this and the front page becomes a
  # scroll rather than a table of contents.
  SHOWCASES_SHOWN = 8

  # How many of the most-liked pages the front page shows, and how low a score is still
  # worth showing. A page with no likes is not "popular"; it is a page, and it belongs in
  # the directory below rather than in a ranking.
  POPULAR_SHOWN = 6

  # How many of a page's own colours to lift for its thumbnail, and how much of the
  # stylesheet to read looking for them.
  THUMBNAIL_COLOURS = 3
  THUMBNAIL_SCAN_BYTES = 4_000

  def home
    # The rices first, because a rice is the thing worth looking at: `joins(:shots)` so
    # only showcases that actually have a picture are considered, then `cover` picks the
    # first attached one. Ordered by change, because this is the gallery and a gallery is
    # ordered by what is new.
    @showcases = Showcase.includes(:user, shots: { image_attachment: :blob })
      .joins(:shots).distinct.order(updated_at: :desc).limit(SHOWCASES_SHOWN * 3)
      .select(&:cover).first(SHOWCASES_SHOWN)

    # The popular pages: the ones people said they liked, most first. A score is the only
    # thing on this page that comes from other people rather than from the page's owner.
    # Ties break on the page's own change time so the order is stable.
    @popular = ranked_pages

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

  private
    # The front page's ranking: the pages people reacted to, most-reacted-to first.
    #
    # Not the average. A page with fifty likes and fifty dislikes has an average of nothing
    # and a hundred people who cared, and a ranking by average buries it under a page one
    # person clicked once. What rises here is the extreme reaction, in either direction —
    # a page everybody loved and a page everybody hated are both more interesting than a
    # page nobody noticed, and this list says so.
    #
    # One grouped read for the counts rather than a query per page. Ties break on the net
    # score, so between two equally-reacted-to pages the better-liked one leads.
    def ranked_pages
      counts = Rating.group(:user_id).pluck(
        Arel.sql("user_id"),
        Arel.sql("SUM(CASE WHEN score = 1 THEN 1 ELSE 0 END)"),
        Arel.sql("SUM(CASE WHEN score = -1 THEN 1 ELSE 0 END)")
      ).to_h { |id, likes, dislikes| [ id, { likes: likes.to_i, dislikes: dislikes.to_i } ] }

      # A page nobody rated is not in this list; it belongs in the directory below.
      counts.reject! { |_id, tally| (tally[:likes] + tally[:dislikes]).zero? }
      return [] if counts.empty?

      users = User.where(id: counts.keys).includes(:profile_picture).index_by(&:id)

      counts
        .sort_by do |id, tally|
          total = tally[:likes] + tally[:dislikes]
          net = tally[:likes] - tally[:dislikes]
          [ -total, -net, id ]
        end
        .filter_map do |id, tally|
          user = users[id]
          next unless user

          { user: user, net: tally[:likes] - tally[:dislikes], total: tally[:likes] + tally[:dislikes] }
        end
        .first(POPULAR_SHOWN)
    end
end
