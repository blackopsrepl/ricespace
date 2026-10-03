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
            blurbs: current_user.blurbs.in_order.map { |blurb| { title: blurb.title, body: blurb.body } }
          }
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
              specs: entry["specs"], cooling: entry["cooling"], details: entry["details"]
            )
          end

          commit(current_user.builds, records, "build")
        end

        def replace_blurbs(raw)
          records = entries(raw).map do |entry|
            current_user.blurbs.build(title: entry["title"], body: entry["body"])
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
        def commit(collection, records, label)
          invalid = records.reject(&:valid?)
          if invalid.any?
            invalid.each do |record|
              @errors += record.errors.full_messages.map { |message| "#{label}: #{message}" }
            end
            return
          end

          collection.destroy_all
          records.each do |record|
            @errors += record.errors.full_messages.map { |m| "#{label}: #{m}" } unless record.save
          end
        end
    end
  end
end
