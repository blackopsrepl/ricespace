ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# The rate limit counters live in one store for the life of the process, so a test
# that deliberately exhausts a limit would otherwise leave the next test locked out.
# Cleared around every test.
module RateLimitReset
  def before_setup
    super
    ApplicationController::RATE_LIMIT_STORE.clear
  end

  def after_teardown
    ApplicationController::RATE_LIMIT_STORE.clear
    super
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include RateLimitReset
  end
end
