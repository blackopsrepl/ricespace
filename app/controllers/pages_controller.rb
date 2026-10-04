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

    # Replicated feeds this node holds: the local view of the network. Same
    # ranking rule as above (reactions lift the page, most-reacted first) —
    # computed over what this node actually verified, not a global list.
    @peer_pages = ranked_peers
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
    # A page's tally is the page plus everything posted on it, because that is how the page
    # itself counts — see User#score. Liking the rice on somebody's page lifts the page.
    #
    # One grouped read for the tallies rather than a query per page, and one more to resolve
    # which account each reacted-to thing belongs to. Ties break on the net score, so between
    # two equally-reacted-to pages the better-liked one leads.
    def ranked_pages
      tallies = Rating.group(:rateable_type, :rateable_id).pluck(
        Arel.sql("rateable_type"),
        Arel.sql("rateable_id"),
        Arel.sql("SUM(CASE WHEN score = 1 THEN 1 ELSE 0 END)"),
        Arel.sql("SUM(CASE WHEN score = -1 THEN 1 ELSE 0 END)")
      ).to_h { |type, id, likes, dislikes| [ [ type, id ], { likes: likes.to_i, dislikes: dislikes.to_i } ] }

      owners = owners_of(tallies.keys)

      per_page = Hash.new { |hash, key| hash[key] = { likes: 0, dislikes: 0 } }
      tallies.each do |(type, id), tally|
        owner_id = owners[[ type, id ]]
        next if owner_id.nil?

        per_page[owner_id][:likes] += tally[:likes]
        per_page[owner_id][:dislikes] += tally[:dislikes]
      end

      # A page nobody reacted to is not in this list; it belongs in the directory below.
      per_page.reject! { |_id, tally| (tally[:likes] + tally[:dislikes]).zero? }
      return [] if per_page.empty?

      users = User.where(id: per_page.keys).includes(:profile_picture).index_by(&:id)

      per_page
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

    # Which account each reacted-to thing belongs to, by `[type, id]`.
    #
    # A page belongs to itself; the things posted on a page belong to their owner. Resolved in
    # one read per kind rather than per row, and by the same `owner` the models use, so the
    # ranking cannot disagree with the page about whose rice it is.
    def owners_of(pairs)
      by_type = pairs.group_by(&:first)

      owners = {}
      by_type.each do |type, type_pairs|
        klass = type.constantize
        ids = type_pairs.map(&:last)

        klass.where(id: ids).includes(owner_includes_for(klass)).each do |thing|
          owner = thing.respond_to?(:owner) ? thing.owner : nil
          owners[[ type, thing.id ]] = owner&.id
        end
      end
      owners
    end

    # The association to preload so `owner` does not fire a query per thing.
    def owner_includes_for(klass)
      case klass.name
      when "ShowcaseShot" then :showcase
      when "BuildPhoto" then :build
      else []
      end
    end

    # Replicated pages, ranked by the same rule as local ones: most reacted-to
    # first, ties to the better-liked. A peer's tally is its page plus
    # everything posted on it, because that is how every page counts.
    def ranked_peers
      tallies = Hash.new { |hash, key| hash[key] = { likes: 0, dislikes: 0 } }
      PeerRecord.where(kind: "reaction").each do |record|
        body = record.parsed_body
        feed = body["target_feed"]
        next if feed.blank?

        if body["opinion"] == "dislike"
          tallies[feed][:dislikes] += 1
        else
          tallies[feed][:likes] += 1
        end
      end

      tallies.reject! { |_feed, tally| (tally[:likes] + tally[:dislikes]).zero? }
      return [] if tallies.empty?

      peers = Peer.where(pubkey: tallies.keys).index_by(&:pubkey)
      tallies
        .sort_by do |feed, tally|
          total = tally[:likes] + tally[:dislikes]
          net = tally[:likes] - tally[:dislikes]
          [ -total, -net, feed ]
        end
        .filter_map do |feed, tally|
          peer = peers[feed]
          next if peer.nil? || peer.latest_document.nil?

          { peer: peer, net: tally[:likes] - tally[:dislikes], total: tally[:likes] + tally[:dislikes] }
        end
        .first(POPULAR_SHOWN)
    end
end
