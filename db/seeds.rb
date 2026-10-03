# This file should ensure the existence of records required to run the application in every
# environment (development, test, production). The data can then be loaded with the command
# bin/rails db:seed (or created alongside the database with db:setup).
#
# Idempotent: `bin/rails db:seed:replant` runs it as part of the CI gate, so every
# statement is a find-or-create rather than a bare insert.

# Ron is the site's own account, and its admin: the default first friend, the way the
# era's sites opened with their founder already on your list. He is the one account
# allowed a reserved username, which is why the row is created as an admin.
ron = User.find_or_initialize_by(username: User::RON)
if ron.new_record?
  ron.assign_attributes(
    admin: true,
    name: "Ron",
    email_address: "ron@ricespace.example",
    password: "correct horse battery staple",
    greeting: "hey, thanks for adding me — i'm ron, i run the place",
    mood: "based",
    headline: "your first friend"
  )
  ron.save!
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
