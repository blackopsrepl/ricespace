# frozen_string_literal: true

namespace :demo do
  desc "Populate the curated demo spaces without replacing accounts or credentials"
  task populate: :environment do
    DemoSite::Writer.new.call
  end
end
