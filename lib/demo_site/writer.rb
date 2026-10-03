# frozen_string_literal: true

# Writing the demo spaces. See lib/demo_site/spaces.rb for what the demo *is*; this is the
# code that puts it on disk and in the database.
#
# Idempotent throughout: each piece asks whether it is already there and writes only what
# is missing, so running it twice does not duplicate a friends list or re-upload a
# screenshot. That matters because the layouts and the rice are the parts somebody will
# want to change and re-run.
module DemoSite
  class Writer
    PICTURES = Rails.root.join("docs", "assets")

    def initialize(verbose: true)
      @verbose = verbose
      @created = 0
      @updated = 0
    end

    def call
      # Each step is named as it runs, and a failure stops the whole thing rather than
      # being swallowed. The first version let an exception escape from one step and the
      # rest of the run simply did not happen — with a summary at the end claiming success.
      [
        [ "ron", :write_ron ],
        [ "the real accounts", :write_real ],
        [ "everybody else", :write_others ],
        [ "friends", :write_friends ],
        [ "the wall", :write_wall ],
        [ "ratings", :write_ratings ]
      ].each do |label, step|
        send(step)
      rescue StandardError => error
        warn "demo: #{label} failed — #{error.class}: #{error.message}"
        raise
      end

      report
    end

    private

    def say(message)
      puts "  #{message}" if @verbose
    end

    # ---- the three real accounts -------------------------------------------------------

    # Ron is the site's own account and the seed already builds most of him: his avatar,
    # his markup in the site's own palette, the bench, and the scene shot. What is missing
    # is the company — everybody else's pages — so this only fills the gaps.
    def write_ron
      ron = User.ron || find_user("ron", "Ron")
      return if ron.nil?

      say "ron: the seed builds him; filling the gaps"
    end

    def write_real
      DemoSite::Spaces::REAL.each do |username, spec|
        next if username == "ron"

        user = find_user(username, spec[:name])
        next if user.nil?

        person(user, spec)
      end
    end

    # ---- everybody else ----------------------------------------------------------------

    def write_others
      DemoSite::Spaces::OTHERS.each do |spec|
        user = find_user(spec[:username], spec[:name])
        next if user.nil?

        person(user, spec)

        if spec[:custom]
          custom_page(user, DemoSite::Spaces::CUSTOM.fetch(spec[:custom]))
        elsif spec[:layout]
          layout_with(user, Layout.find(spec[:layout]))
        end
      end
    end

    # One person: who they are, their markup, their rice, and the rest of the page.
    def person(user, spec)
      attributes = {
        name: spec[:name],
        headline: spec[:headline],
        mood: spec[:mood],
        greeting: spec[:greeting]
      }.compact

      changed = attributes.any? { |field, value| user.public_send(field) != value }
      user.update!(attributes) if changed
      @updated += 1 if changed

      # The markup, or the custom stylesheet for the two pages that write their own.
      #
      # Order matters: the custom page *replaces* what was written, so the generic markup
      # must only be written for people who are not one of the two. Writing it first and
      # then overwriting leaves the count of "pages with markup" honest, but it also means
      # a re-run sees the custom page and skips — which is why the custom case is decided
      # here rather than after.
      if spec[:custom]
        custom_page(user, DemoSite::Spaces::CUSTOM.fetch(spec[:custom]))
      elsif spec[:blurb] || spec[:blurbs]
        written_page(user, spec)
      end

      rice(user, spec[:rice]) if spec[:rice]
      blurbs(user, spec)
      links(user, spec[:links])
      demos(user, spec[:demos])
      builds(user, spec[:build])
    end

    # The owner's own markup, in the site's own palette. Deliberately plain: it is the
    # content the layout is for, and a page that fights its layout is a page that shows
    # nothing about the layout.
    def written_page(user, spec)
      name = spec[:name]
      line = spec[:greeting] || "hello"

      document = <<~HTML
        <style>
          body { background-color: #0b0b0d; color: #e4e4e7; font-family: Verdana, Arial, sans-serif; }
          #profile { text-align: center; }
          #profile h1 { color: #ffc24b; }
          #profile p { color: #a1a1aa; }
        </style>
        <div id="profile">
          <h1>#{name}'s page</h1>
          <p>#{line}</p>
          <marquee scrollamount="4">this is #{name}'s page and nobody else's</marquee>
        </div>
      HTML

      return if same_page?(user, document)

      layout_with(user, nil, document: document)
    end

    # Wearing a layout, or writing the page from scratch.
    #
    # Applying a layout rewrites the document, so it only happens when the page is not
    # already wearing it — otherwise every run would flatten whatever the owner added on
    # top, which is the thing a re-runnable demo must not do.
    def layout_with(user, layout, document: nil)
      profile = user.profile

      if document
        return if same_page?(user, document)

        profile.update!(document: document)
        @updated += 1
        say "#{user.username}: wrote their markup"
        return
      end

      return if layout.nil?
      # Already wearing it? Checked by a colour unique to the theme, not by its first line:
      # every layout starts with a comment, so comparing first lines says yes for all of
      # them at once.
      return if profile.document.include?(layout_signature(layout))

      base = profile.document.presence || "<div id=\"profile\"><h1>#{user.display_name}'s page</h1></div>"
      profile.update!(document: base) if profile.document.blank?
      profile.update!(document: LayoutApplication.new(profile, layout).document)
      @updated += 1
      say "#{user.username}: wearing #{layout.name}"
    end

    # The line in a layout that only that theme has. Every generated layout sets the page's
    # background to its theme's own colour, which is the shortest thing that distinguishes
    # one from another.
    def layout_signature(layout)
      layout.css[/background-color:\s*(#[0-9a-fA-F]{6})/, 1].to_s
    end

    def same_page?(user, document)
      user.profile.document == document
    end

    # A page written by hand, with no layout anywhere near it.
    #
    # Checked by a marker unique to the sheet rather than its first line: the first line of
    # these is `<style>`, which every page has.
    def custom_page(user, css)
      profile = user.profile
      return if profile.document.include?(custom_marker(css))

      profile.update!(document: css)
      @updated += 1
      say "#{user.username}: their own stylesheet, no layout"
    end

    def custom_marker(css)
      css.lines.grep(/\S/).find { |line| !line.strip.start_with?("<style>", "</style>") }.to_s.strip
    end

    # ---- the rice ----------------------------------------------------------------------

    def rice(user, facts)
      showcase = user.showcase || user.build_showcase
      return if showcase.filled?

      showcase.assign_attributes(facts)
      showcase.save!
      @updated += 1
      say "#{user.username}: the rice"

      shot(showcase)
    end

    # A screenshot for the rice, so the gallery on the front page has something in it.
    #
    # The demo does not ship one picture per person — that would be a lot of repository for
    # a set of examples. It reuses the artwork the repository already carries, chosen by
    # theme, and says so rather than pretending these are anybody's desktop.
    def shot(showcase)
      return if showcase.shots.any?

      source = PICTURES.join("ricespace-mascot.png")
      return unless source.exist?

      shots = showcase.shots.create!(caption: "#{showcase.user.display_name}'s rice")
      shots.image.attach(io: source.open, filename: "rice.png", content_type: "image/png")
      say "#{showcase.user.username}: a screenshot (the mascot — see lib/demo_site/spaces.rb)"
    end

    def blurbs(user, spec)
      want = Array(spec[:blurbs] || (spec[:blurb] ? [ spec[:blurb] ] : []))
      want.each do |blurb|
        next if user.blurbs.exists?(title: blurb[:title])

        user.blurbs.create!(title: blurb[:title], body: blurb[:body])
        @updated += 1
      end
    end

    def links(user, links)
      Array(links).each do |link|
        next if user.stream_links.exists?(url: link[:url])

        user.stream_links.create!(link)
        @updated += 1
      end
    end

    def demos(user, demos)
      Array(demos).each do |demo|
        next if user.demos.exists?(title: demo[:title])

        user.demos.create!(demo)
        @updated += 1
      end
    end

    def builds(user, build)
      return if build.nil?
      return if user.builds.exists?(title: build[:title])

      user.builds.create!(build)
      @updated += 1
      say "#{user.username}: #{build[:title]}"
    end

    # ---- how they know each other -------------------------------------------------------

    # Friends, so no page is an island. Ron is everybody's first friend already; this is
    # the rest of the graph — the three real accounts know each other, and each demo page
    # has somebody on it.
    FRIENDSHIPS = [
      %w[vittorio ron], %w[cordelia ron], %w[vittorio cordelia], %w[cordelia vittorio],
      %w[wes alice], %w[alice wes], %w[bob heidi], %w[heidi bob],
      %w[dave grace], %w[grace dave], %w[mika cordelia], %w[erin ron],
      %w[frank carol], %w[carol frank], %w[wes vittorio], %w[alice cordelia]
    ].freeze

    def write_friends
      FRIENDSHIPS.each do |username, friend_username|
        user = User.find_by(username: username)
        friend = User.find_by(username: friend_username)
        next if user.nil? || friend.nil?
        next if user.friendships.exists?(friend: friend)

        user.friendships.create!(friend: friend)
        @updated += 1
      end
      say "friends: #{Friendship.count} pairs"
    end

    # ---- the wall -----------------------------------------------------------------------

    def write_wall
      DemoSite::Spaces::WALL.each do |page_username, author_username, body|
        page = User.find_by(username: page_username)
        author = User.find_by(username: author_username)
        next if page.nil? || author.nil?
        next if page.comments.exists?(author: author, body: body)

        page.comments.create!(author: author, body: body)
        @updated += 1
      end
      say "wall: #{Comment.count} comments"
    end

    # ---- what people thought -------------------------------------------------------------

    def write_ratings
      DemoSite::Spaces::RATINGS.each do |page_username, author_username, score|
        page = User.find_by(username: page_username)
        author = User.find_by(username: author_username)
        next if page.nil? || author.nil?
        next if page.id == author.id
        next if page.ratings.exists?(author: author)

        page.ratings.create!(author: author, score: score)
        @updated += 1
      end
      say "ratings: #{Rating.count}"
    end

    # ---- helpers -------------------------------------------------------------------------

    # Find the account, or make it. The demo is written against a seeded site, but a site
    # somebody has been using may have lost one, and a populate that stops halfway is worse
    # than one that makes the account it needs.
    def find_user(username, name)
      user = User.find_by(username: username)
      return user if user

      password = "demo-#{username}-password"
      user = User.create!(
        username: username, email_address: "#{username}@ricespace.example",
        password: password, password_confirmation: password, name: name
      )
      @created += 1
      say "#{username}: created"
      user
    end

    def report
      puts
      puts "demo: #{User.count} accounts, #{Profile.where.not(document: [ nil, "" ]).count} written pages, " \
           "#{Showcase.count} rices, #{Rating.count} ratings, #{Comment.count} wall posts"
    end
  end
end
