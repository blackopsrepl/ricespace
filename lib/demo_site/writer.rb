# frozen_string_literal: true

module DemoSite
  # Populate page content without replacing accounts, credentials or uploaded pictures.
  class Writer
    FRIENDSHIPS = [
      %w[vittorio ron], %w[cordelia ron], %w[vittorio cordelia], %w[cordelia vittorio],
      %w[wes alice], %w[alice wes], %w[bob heidi], %w[heidi bob],
      %w[dave grace], %w[grace dave], %w[mika cordelia], %w[erin ron],
      %w[frank carol], %w[carol frank], %w[wes vittorio], %w[alice cordelia],
      %w[ivan grace], %w[judy carol], %w[oscar mika]
    ].freeze

    def initialize(verbose: true)
      @verbose = verbose
    end

    def call
      User.transaction do
        Spaces::REAL.each do |username, spec|
          populate(find_user(username, spec[:name]), spec)
        end
        Spaces::OTHERS.each do |spec|
          populate(find_user(spec[:username], spec[:name]), spec)
        end
        friendships
        comments
        ratings
        post_reactions
      end
      puts "demo: #{User.count} accounts, #{Profile.where.not(document: [ nil, "" ]).count} written pages, " \
        "#{Showcase.count} rices, #{Rating.count} reactions " \
        "(#{Rating.where(rateable_type: "User").count} on pages, " \
        "#{Rating.where.not(rateable_type: "User").count} on posts), #{Comment.count} wall posts" if @verbose
    end

    private
      def find_user(username, name)
        User.find_by(username: username) || User.create!(
          username: username, name: name, admin: username == User::RON,
          email_address: "#{username}@ricespace.example", password: SecureRandom.hex(32)
        )
      end

      def populate(user, spec)
        user.assign_attributes(spec.slice(:name, :headline, :mood, :greeting))
        user.save! if user.changed?
        document = document_for(spec)
        user.profile.update!(document: document) unless user.profile.document == document

        if spec[:rice]
          showcase = user.showcase || user.build_showcase
          showcase.assign_attributes(spec[:rice])
          showcase.save! if showcase.new_record? || showcase.changed?
          screenshot(showcase)
        end
        if spec[:interests]
          user.profile.update!(interests: spec[:interests]) unless user.profile.interests == spec[:interests]
        end
        if spec[:song]
          user.profile.update!(spec[:song]) unless user.profile.song? && user.profile.song_url == spec[:song][:song_url]
        end
        Array(spec[:blurbs] || (spec[:blurb] ? [ spec[:blurb] ] : [])).each do |blurb|
          record = user.blurbs.find_or_initialize_by(title: blurb.fetch(:title))
          record.assign_attributes(blurb)
          record.save! if record.new_record? || record.changed?
        end
        Array(spec[:links]).each do |link|
          user.stream_links.find_or_create_by!(url: link.fetch(:url)) { |record| record.assign_attributes(link) }
        end
        Array(spec[:demos]).each do |demo|
          user.demos.find_or_create_by!(title: demo.fetch(:title)) { |record| record.assign_attributes(demo) }
        end
        if spec[:build]
          build = spec[:build]
          user.builds.find_or_create_by!(title: build.fetch(:title)) { |record| record.assign_attributes(build) }
        end
        puts "  #{user.username}: #{spec[:layout] || spec[:custom] || "own page"}" if @verbose
      end

      def document_for(spec)
        return Spaces::PAGES.fetch(spec[:page]) if spec[:page]
        return Spaces::CUSTOM.fetch(spec[:custom]) if spec[:custom]

        markup = <<~HTML
          <div class="demo-intro">
            <h1>#{ERB::Util.html_escape(spec[:name])}'s corner</h1>
            <p>#{ERB::Util.html_escape(spec[:greeting])}</p>
            <marquee scrollamount="3">#{ERB::Util.html_escape(spec[:headline])}</marquee>
          </div>
        HTML
        profile = Profile.new(document: markup)
        LayoutApplication.new(profile, Layout.find(spec.fetch(:layout)), keep_own_rules: false).document
      end

      # The rice's picture, for a showcase that has none.
      #
      # Drawn, not looked up: the desktop in the picture is built from the same facts the page
      # lists beside it — this window manager, this bar, this terminal, this font, this theme —
      # so the picture cannot contradict the page, and a new demo account gets a rice without
      # anybody drawing one by hand. See `DemoSite::RiceArt`.
      def screenshot(showcase)
        return if showcase.shots.any?

        shot = showcase.shots.create!(caption: "#{showcase.user.display_name}'s rice")
        shot.image.attach(
          io: StringIO.new(art_for(showcase)),
          filename: "#{showcase.user.username}-rice.png",
          content_type: "image/png"
        )
      end

      # The rice says its theme as words ("tokyo night"); the art knows the colours by the
      # layout's name ("tokyo-night"), so the two are reconciled rather than asked for twice.
      def art_for(showcase)
        facts = showcase.facts.to_h.symbolize_keys
        RiceArt.draw(
          theme: showcase.theme.to_s.tr(" ", "-").downcase,
          name: showcase.user.display_name,
          facts: {
            wm: facts[:window_manager], bar: facts[:bar], term: facts[:terminal],
            font: facts[:font], theme: showcase.theme, host: showcase.user.username
          }
        )
      end

      def friendships
        FRIENDSHIPS.each do |username, friend_username|
          user = User.find_by!(username: username)
          user.friendships.find_or_create_by!(friend: User.find_by!(username: friend_username))
        end
      end

      def comments
        Spaces::WALL.each do |username, author_username, body|
          User.find_by!(username: username).comments.find_or_create_by!(
            author: User.find_by!(username: author_username), body: body
          )
        end
      end

      def ratings
        Spaces::RATINGS.each do |username, author_username, score|
          page = User.find_by!(username: username)
          page.reactions.find_or_create_by!(
            author: User.find_by!(username: author_username)
          ) { |rating| rating.score = score }
        end
      end

      # Reactions on the things people posted rather than on their pages — the rice, a build,
      # a demo. `first_of` picks the owner's first thing of that kind, so the fixture names a
      # kind and not an id that changes every time the database is rebuilt.
      def post_reactions
        Spaces::POST_REACTIONS.each do |username, kind, author_username, score|
          thing = first_of(User.find_by!(username: username), kind)
          next if thing.nil?

          thing.reactions.find_or_create_by!(
            author: User.find_by!(username: author_username)
          ) { |rating| rating.score = score }
        end
      end

      # The owner's first posted thing of a kind, by the same names the routes use.
      def first_of(owner, kind)
        case kind
        when "showcase" then owner.showcase
        when "shot" then owner.showcase&.shots&.first
        when "build" then owner.builds.first
        when "photo" then owner.builds.flat_map(&:photos).first
        when "demo" then owner.demos.first
        when "link" then owner.stream_links.first
        when "blurb" then owner.blurbs.first
        end
      end
  end
end
