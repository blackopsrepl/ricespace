# frozen_string_literal: true

module Api
  module V1
    # The bits of a page that are not its markup: the links, the demos, the hardware, the
    # friends, the blurbs. Each is a list with its own facts, and each is the same record
    # the studio edits — a second way into one thing, not a second thing.
    #
    # Collection-wide reads and writes, because these are lists a client manages as a
    # whole: `GET` returns every entry, `PUT` replaces the list with what was sent. That
    # is what makes `ricespace links set …` idempotent in a terminal, where creating and
    # deleting one at a time is the wrong shape for a config file or a shell script.
    class PageController < BaseController
      # GET /api/v1/page — everything on the page that is not its markup.
      def show
        render json: { page: presentation }
      end

      # PUT /api/v1/page — replace the lists that were sent, leaving the rest alone.
      #
      # Whole-list replacement, atomic per kind: every entry of a list is validated before
      # any of it is written, so a refused entry cannot leave a page half rewritten. A key
      # that was not sent is untouched; a key sent as an empty list is cleared. That is the
      # distinction that makes this idempotent from a shell script.
      def update
        @errors = []
        sent = params.require(:page)

        replace_links(sent[:links]) if sent.key?(:links)
        replace_demos(sent[:demos]) if sent.key?(:demos)
        replace_builds(sent[:builds]) if sent.key?(:builds)
        replace_friends(sent[:friends]) if sent.key?(:friends)
        replace_blurbs(sent[:blurbs]) if sent.key?(:blurbs)
        # The order of the rice's shots, as one list of ids. A folder holds one order, and
        # the alternative is a `move` per picture — N requests to say one thing.
        reorder_shots(sent[:shot_order]) if sent.key?(:shot_order)

        return if @errors.any? && fail_with(:unprocessable_content, "invalid_page",
          "some entries were refused", details: @errors)

        render json: { page: presentation }
      end

      private
        # One entry of a list, as a plain hash. Rails hands these over as
        # ActionController::Parameters, which is not a Hash and answers `is_a?(Hash)` with
        # false — reading them as hashes is what makes `entry["username"]` work at all.
        def entry_hash(entry)
          case entry
          when ActionController::Parameters then entry.to_unsafe_h
          when Hash then entry
          else {}
          end
        end

        # The entries of a sent list, with the ones that carry nothing dropped — an empty
        # array and a single empty entry mean the same thing from a shell, and neither
        # should be read as "make me a blank entry".
        def entries(raw)
          Array(raw).map { |entry| entry_hash(entry) }.reject(&:empty?)
        end

        def presentation
          {
            username: current_user.username,
            url: profile_url(current_user.username),
            picture: picture_presentation,
            links: current_user.stream_links.order(:created_at).map do |link|
              { platform: link.platform, url: link.url, title: link.title }
            end,
            demos: current_user.demos.in_order.map do |demo|
              {
                title: demo.title, group: demo.group_name, party: demo.party,
                year: demo.release_year, platform: demo.platform, category: demo.category,
                placing: demo.ranking, url: demo.url, note: demo.watch_note,
                embeds: !demo.embed.nil?
              }
            end,
            builds: current_user.builds.in_order.map do |build|
              {
                title: build.title, kind: build.kind, summary: build.summary,
                specs: build.specs, cooling: build.cooling, details: build.details,
                photos: build.photos.map { |photo| { caption: photo.caption, position: photo.position } }
              }
            end,
            friends: current_user.friendships.in_order.map { |friendship| friendship.friend.username },
            blurbs: current_user.blurbs.in_order.map { |blurb| { title: blurb.title, body: blurb.body } },
            shots: shot_list
          }
        end

        # The rice's shots, in order, with the ids a folder keeps so it can name them again.
        # Present here as well as on the showcase endpoint because a folder holds one page and
        # should not need two reads to render it.
        def shot_list
          (current_user.showcase&.shots || []).map do |shot|
            {
              id: shot.id, caption: shot.caption, position: shot.position,
              bytes: shot.image.attached? ? shot.image.blob.byte_size : nil,
              url: shot.image.attached? ? rails_blob_url(shot.image.blob) : nil
            }
          end
        end

        def picture_presentation
          picture = current_user.profile_picture
          return nil if picture.nil? || !picture.image.attached?

          { url: rails_blob_url(picture.image.blob), bytes: picture.image.blob.byte_size }
        end

        # Set the rice's shot order from a list of ids. Ids that are not this account's are
        # ignored, and anything unnamed keeps its place afterwards: a folder that has drifted
        # should converge rather than be refused.
        def reorder_shots(raw)
          ids = Array(raw).map(&:to_i)
          owned = current_user.showcase&.shots&.to_a || []
          return if owned.empty?

          by_id = owned.index_by(&:id)
          ordered = ids.filter_map { |id| by_id[id] }
          ordered += owned.reject { |shot| ids.include?(shot.id) }

          ordered.each_with_index { |shot, position| shot.update_column(:position, position) }
        end

        # Each replacement is whole-list and atomic per kind: the old entries go only
        # after every new one is valid, so a refused entry cannot leave a page half
        # rewritten.
        def replace_links(raw)
          records = entries(raw).map do |entry|
            current_user.stream_links.build(url: entry["url"], title: entry["title"])
          end

          commit(current_user.stream_links, records, "link")
        end

        def replace_demos(raw)
          records = entries(raw).map do |entry|
            current_user.demos.build(
              title: entry["title"], group_name: entry["group"],
              party: entry["party"], release_year: entry["year"],
              platform: entry["platform"], category: entry["category"],
              ranking: entry["placing"], url: entry["url"], watch_note: entry["note"]
            )
          end

          commit(current_user.demos, records, "demo")
        end

        def replace_builds(raw)
          records = entries(raw).map do |entry|
            current_user.builds.build(
              title: entry["title"], kind: entry["kind"], summary: entry["summary"],
              # The column is NOT NULL and the model allows blank, so an omitted field has to
              # become the empty string it defaults to — sending nil reaches SQLite as a
              # constraint violation, which is a 500 where the client deserves an answer.
              specs: entry["specs"].to_s, cooling: entry["cooling"].to_s, details: entry["details"].to_s
            )
          end

          commit(current_user.builds, records, "build")
        end

        def replace_blurbs(raw)
          records = entries(raw).map do |entry|
            current_user.blurbs.build(title: entry["title"], body: entry["body"].to_s)
          end

          commit(current_user.blurbs, records, "blurb")
        end

        def replace_friends(raw)
          usernames = entries(raw).map { |entry| entry["username"].to_s }
          usernames.reject!(&:blank?)
          friends = usernames.map { |name| User.find_by(username: name.strip.downcase) }

          missing = usernames.zip(friends).reject { |_name, user| user }.map(&:first)
          if missing.any?
            return (@errors += missing.map { |name| "no page with the username #{name.inspect}" })
          end

          records = friends.map { |friend| current_user.friendships.build(friend: friend) }
          commit(current_user.friendships, records, "friend")
        end

        # Validate everything first, then swap. A list that fails validation is reported
        # whole, and the page is left exactly as it was.
        #
        # The swap runs inside a transaction and the old entries go *before* the new ones are
        # saved, because this is a whole-list replacement: a friend who is still on the list is
        # not a duplicate, they are the list, and judging uniqueness against the old rows makes
        # setting the same friends twice impossible. Any failure rolls the old list back, so a
        # refused entry still cannot leave the page half rewritten.
        def commit(collection, records, label)
          failures = []

          collection.transaction do
            collection.destroy_all

            records.each do |record|
              failures += record.errors.full_messages.map { |message| "#{label}: #{message}" } unless record.save
            end

            raise ActiveRecord::Rollback if failures.any?
          end

          @errors += failures
        rescue ActiveRecord::NotNullViolation, ActiveRecord::StatementInvalid => error
          @errors << "#{label}: #{error.message.split("\n").first}"
        end
    end
  end
end
