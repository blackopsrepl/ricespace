# frozen_string_literal: true

# An account on RiceSpace. A user owns exactly one profile page and may issue
# agent tokens, which let a coding agent edit that profile on the owner's
# behalf.
class User < ApplicationRecord
  has_secure_password

  # Usernames appear in profile URLs, so they are restricted to the characters
  # that are safe to put in a path without escaping and that cannot be confused
  # with another account (case is folded away, and names that the site itself
  # might want are refused).
  USERNAME_FORMAT = /\A[a-z0-9](?:[a-z0-9-]{1,28}[a-z0-9])?\z/
  RESERVED_USERNAMES = %w[
    admin api assets about account auth help home legal login logout me new
    profiles root settings sign-in sign-out sign-up static studio support up
    ron
  ].freeze

  # The site's own account. The era's sites opened with their founder already on
  # your friends list; here that account is Ron, and every new page starts with
  # him on it. His name is one of the reserved ones — being the site's own
  # account is what exempts him from the rule that reserves it.
  RON = "ron"

  # Long enough that a profile page is not the softest target in the account.
  MINIMUM_PASSWORD_LENGTH = 12

  has_one :profile, dependent: :destroy
  has_one :profile_picture, dependent: :destroy
  has_one :showcase, dependent: :destroy
  has_many :agent_tokens, dependent: :destroy

  # This account's page: the people on its friends list, the blocks of text its
  # owner wrote, and the comments other people left on it.
  has_many :friendships, dependent: :destroy
  has_many :friends, through: :friendships, source: :friend
  has_many :blurbs, dependent: :destroy
  has_many :comments, dependent: :destroy

  # The videos and streams shown on this account's page. Links to somebody else's
  # service — nothing here is hosted by this site.
  has_many :stream_links, dependent: :destroy

  # The demoscene demos listed on this account's page, with the release facts.
  has_many :demos, dependent: :destroy

  # The hardware on this account's page: physical builds, with their photos.
  has_many :builds, dependent: :destroy

  # Where this account appears on somebody else's page. Destroying the account
  # removes it from their lists rather than leaving a hole.
  has_many :reverse_friendships, class_name: "Friendship", foreign_key: :friend_id, dependent: :destroy

  # The published stylesheets this account may apply to its page.
  def layouts
    Layout.all
  end

  normalizes :email_address, with: ->(value) { value.to_s.strip.downcase }
  normalizes :username, with: ->(value) { value.to_s.strip.downcase }
  normalizes :greeting, with: ->(value) { value.to_s.strip }
  normalizes :mood, with: ->(value) { value.to_s.strip }

  validates :email_address, presence: true,
    format: { with: URI::MailTo::EMAIL_REGEXP },
    uniqueness: { case_sensitive: false }
  validates :username, presence: true,
    format: { with: USERNAME_FORMAT, message: "may only contain lowercase letters, digits and hyphens" },
    uniqueness: true
  # The names the site itself needs are refused to everybody except the site's
  # own account, whose name is one of them.
  validates :username, exclusion: { in: RESERVED_USERNAMES, message: "is reserved" }, unless: :admin?
  validates :name, length: { maximum: 60 }, allow_blank: true
  validates :headline, length: { maximum: 140 }, allow_blank: true
  # The greeting is the line across the top of the page, so it is one line.
  validates :greeting, length: { maximum: 140 }, allow_blank: true
  validates :mood, length: { maximum: 40 }, allow_blank: true
  validates :password, length: { minimum: MINIMUM_PASSWORD_LENGTH }, allow_nil: true

  after_create { build_profile.save! unless profile }

  # A new page opens with the site's own account already on its list, first.
  after_create :be_friends_with_ron

  def self.ron
    find_by(username: RON)
  end

  def to_param
    username
  end

  # The name shown for this account anywhere the display name is not set.
  def display_name
    name.presence || username
  end

  private
    def be_friends_with_ron
      return if username == RON

      host = self.class.ron
      return if host.nil?

      friendships.create!(friend: host)
    end
end
