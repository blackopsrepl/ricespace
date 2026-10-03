# frozen_string_literal: true

# The demo spaces: a site with pages on it, for looking at and for showing to somebody.
#
#     bin/rails demo:populate        write it
#     bin/rails demo:reset           write it again from scratch
#
# Deliberately not part of `db:seeds`. Seeding an install should give you a site with its
# owner account on it, not fifteen strangers — but an empty directory is a poor way to
# understand what the site is, so this is here to run when you want to see one full.
namespace :demo do
  desc "Fill the site with demo spaces (Ron, Vittorio, Cordelia, and one page per layout)"
  task populate: :environment do
    DemoSite::Writer.new.call
  end

  desc "Erase the demo pages and write them again"
  task reset: :environment do
    # Everything but the site's own account: Ron is seeded, and the walls and ratings
    # point at him.
    names = DemoSite::Spaces::REAL.keys + DemoSite::Spaces::OTHERS.map { |spec| spec[:username] }
    names -= [ "ron" ]

    puts "removing #{names.size} demo accounts and everything on them"
    User.where(username: names).find_each(&:destroy!)

    # Ron's own page is seeded; clear the demo's additions to it rather than him.
    if (ron = User.ron)
      ron.comments.destroy_all
      ron.reload
    end

    DemoSite::Writer.new.call
  end
end
