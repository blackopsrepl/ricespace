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

  # How much one account may keep in pictures, across everything it has uploaded. The one
  # number: the per-file ceilings on the models bound a single upload, and this bounds the
  # account, so the disk is not shared out by whoever uploads most. Every upload path checks
  # it through `over_storage_limit?` — see `CountedTowardStorage`.
  STORAGE_LIMIT = 200.megabytes

  has_one :profile, dependent: :destroy
  has_one :profile_picture, dependent: :destroy
  has_one :showcase, dependent: :destroy
  has_many :agent_tokens, dependent: :destroy

  # This account's page: the people on its friends list, the blocks of text its
  # owner wrote, and the comments other people left on it.
  has_many :friendships, dependent: :destroy
  has_many :friends, through: :friendships, source: :friend
  has_many :blurbs, dependent: :destroy

  # The comments *on* this account's page, and the comments this account left on other
  # people's. Both have to go with the account, and only one of them is obvious: the first
  # is the page's own wall, the second is every wall this person ever wrote on. Without the
  # second, closing an account fails on a foreign key — the comment it left behind points
  # at a row that no longer exists.
  has_many :comments, dependent: :destroy
  has_many :written_comments, class_name: "Comment", foreign_key: :author_id, dependent: :destroy

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

  # The likes and dislikes left on this account's page, and the ones this account left
  # elsewhere. Both cascade, so a closed account leaves no orphaned votes.
  has_many :ratings, dependent: :destroy
  has_many :given_ratings, class_name: "Rating", foreign_key: :author_id, dependent: :destroy

  # Favorites and blocks — the MySpace "Contacting" section.
  has_many :favorites, dependent: :destroy
  has_many :favorited_users, through: :favorites, source: :favorited_user
  has_many :blocks, dependent: :destroy
  has_many :blocked_users, through: :blocks, source: :blocked_user

  # What people think of this page: likes minus dislikes.
  #
  # Calculated rather than stored. A total in a column is a second copy of the truth that
  # has to be updated on every rating, every change of mind and every closed account, and
  # the one time it is not is the time the number is wrong. This is a SUM over an index.
  def score
    ratings.sum(:score)
  end

  def likes
    ratings.where(score: Rating::LIKE).count
  end

  def dislikes
    ratings.where(score: Rating::DISLIKE).count
  end

  # How this account rated somebody else's page, or nil for no opinion yet.
  def rating_for(other)
    given_ratings.find_by(user_id: other.id)&.score
  end

  # The same thing as the word a client sends and receives: "like", "dislike" or nil.
  # A score is the arithmetic; this is the opinion, and the two are worth keeping apart
  # because only one of them is a person's.
  def rating_value_for(other)
    case rating_for(other)
    when Rating::LIKE then "like"
    when Rating::DISLIKE then "dislike"
    end
  end

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

  # Closing your own account. Everything hanging off it is `dependent: :destroy`, so
  # the page, the picture, the rice, the blurbs, the comments, the friends list and
  # the agent tokens go with it instead of being left behind pointing at nothing.
  def close!
    destroy!
  end

  def to_param
    username
  end

  # The name shown for this account anywhere the display name is not set.
  def display_name
    name.presence || username
  end

  # Every byte of picture this account is storing. Sums the account's own picture, its rice's
  # shots, and every hardware photo, because those are the three places a picture can live and
  # a limit that missed one of them would not be a limit.
  def stored_picture_bytes
    blobs = []
    blobs << profile_picture.image.blob if profile_picture&.image&.attached?
    blobs += ShowcaseShot.where(showcase_id: showcase&.id).filter_map { |shot| shot.image.blob if shot.image.attached? } if showcase
    blobs += BuildPhoto.where(build_id: builds.select(:id)).filter_map { |photo| photo.image.blob if photo.image.attached? }

    blobs.sum(&:byte_size)
  end

  # Whether adding `adding` bytes would take this account past `STORAGE_LIMIT`.
  #
  # `excluding` is the record being written. A picture replacing itself is not a second
  # picture, so what the account *already* stores for that record comes off the total before
  # the new size goes on — and it is read from the database, not from the record in hand: after
  # `attach` the record's `image` is the new, unsaved one, and subtracting that would make a
  # brand-new picture look like it freed space.
  def over_storage_limit?(adding, excluding: nil)
    stored = stored_picture_bytes - stored_bytes_for(excluding)

    (stored + adding.to_i) > STORAGE_LIMIT
  end

  # What the account currently stores for one record, straight from storage. Zero for a record
  # that is not persisted yet, because nothing of it is stored.
  def stored_bytes_for(record)
    return 0 if record.nil? || !record.persisted?

    ActiveStorage::Attachment
      .joins(:blob)
      .where(record_type: record.class.polymorphic_name, record_id: record.id)
      .sum("active_storage_blobs.byte_size")
  end

  private
    def be_friends_with_ron
      return if username == RON

      host = self.class.ron
      return if host.nil?

      friendships.create!(friend: host)
    end
end
