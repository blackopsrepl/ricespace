# This file should ensure the existence of records required to run the application in every
# environment (development, test, production). The data can then be loaded with the command
# bin/rails db:seed (or created alongside the database with db:setup).
#
# Idempotent: `bin/rails db:seed:replant` runs it as part of the CI gate, so every
# statement is a find-or-create rather than a bare insert.

# Ron is the site's own account: its founder, its admin, and everybody's first
# friend. Being the site's own account is what lets him hold a reserved username,
# so the row is created as an admin.
ron = User.find_or_initialize_by(username: User::RON)
if ron.new_record?
  ron.assign_attributes(
    admin: true,
    name: "Ron",
    email_address: "ron@ricespace.example",
    password: "correct horse battery staple",
    greeting: "hey, thanks for adding me — i'm ron, i run the place",
    mood: "based",
    headline: "founder, and your first friend"
  )
  ron.save!
end

# His avatar. The picture ships with the repo under docs/assets, so his page has
# a face the moment the site is seeded rather than an empty box.
AVATAR = Rails.root.join("docs", "assets", "ron-avatar.png")
if AVATAR.exist? && !ron.profile_picture&.image&.attached?
  picture = ron.profile_picture || ron.build_profile_picture
  picture.image.attach(io: AVATAR.open, filename: "ron-avatar.png", content_type: "image/png")
  picture.save!
end

# His page: a greeting in the palette the site itself uses, so the front door of the
# site looks like the house.
unless ron.profile.document.present?
  ron.profile.update!(document: <<~HTML)
    <style>
      body { background-color: #0b0b0d; color: #e4e4e7; font-family: Verdana, Arial, sans-serif; }
      #profile { text-align: center; }
      #profile h1 { color: #ffc24b; letter-spacing: 0.02em; }
      #profile p { color: #a1a1aa; }
    </style>
    <div id="profile">
      <h1>welcome to ricespace</h1>
      <p>you're on the list. everybody is — i'm your first friend, same as always.</p>
      <p>write your page. that's the whole product.</p>
    </div>
  HTML
end

# His rice: the machine the site is built and run from, with the scene art as its
# screenshot so the flagship page is not an empty gallery.
SCENE = Rails.root.join("docs", "assets", "ron.png")
showcase = ron.showcase || ron.build_showcase
unless showcase.filled?
  showcase.assign_attributes(
    title: "the ricespace bench",
    summary: "the build this site runs on, and the room it sits in.",
    hardware: "ryzen 9, 64gb, an unreasonable number of fans",
    window_manager: "sway",
    bar: "waybar",
    terminal: "ghostty",
    font: "iosevka",
    theme: "synthwave — magenta, cyan, chrome"
  )
  showcase.save!

  if SCENE.exist? && showcase.shots.none?
    shot = showcase.shots.create!(caption: "ron at the bench")
    shot.image.attach(io: SCENE.open, filename: "ron.png", content_type: "image/png")
  end
end
