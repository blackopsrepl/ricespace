# frozen_string_literal: true

# A credential an owner hands to a coding agent so it can edit their profile.
#
# The token is shown once, at creation, and only its digest is stored: a leaked
# database cannot be replayed against the API. Tokens are random above any
# guessable size, so a fast digest is sufficient for lookup and no password
# hashing is involved.
class AgentToken < ApplicationRecord
  PREFIX = "rs_"
  TOKEN_BYTES = 24
  TOKEN_FORMAT = /\A#{PREFIX}[0-9a-f]{#{TOKEN_BYTES * 2}}\z/

  belongs_to :user

  # The plaintext token, populated only on the instance that issued it.
  attr_reader :plaintext

  validates :name, presence: true, length: { maximum: 60 }

  scope :recent_first, -> { order(created_at: :desc) }

  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  # Returns the token record for a bearer token, or nil when the token is
  # malformed or unknown. Records the use so an owner can see stale tokens.
  def self.authenticate(token)
    return nil unless token.is_a?(String) && token.match?(TOKEN_FORMAT)

    find_by(token_digest: digest(token))&.tap do |record|
      record.update_column(:last_used_at, Time.current)
    end
  end

  # Issues a token for a user and returns the record, whose #plaintext holds the
  # only copy of the secret that will ever exist.
  def self.issue(user:, name:)
    token = "#{PREFIX}#{SecureRandom.hex(TOKEN_BYTES)}"
    record = user.agent_tokens.create!(name: name, token_digest: digest(token))
    record.instance_variable_set(:@plaintext, token)
    record
  end
end
