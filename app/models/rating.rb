# frozen_string_literal: true

# ricespace — a page per account, and the HTML and CSS to fill it.
# Copyright (C) 2026 Vittorio
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option) any
# later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <https://www.gnu.org/licenses/>.

# One account's opinion of one posted thing.
#
# A reaction is a single like or dislike, not a count, and there is one per pair: a person
# reacts to a thing once and changing their mind edits that reaction. That is what keeps the
# number meaning "how many people said yes" instead of "how many times the button was
# pressed", which is the difference between an old-school popularity score and a metric.
#
# What was reacted to is a pair — a kind and an id — so the same act works on a page, a rice,
# a shot of that rice, a build, a demo or a link. The score of any of them is a `SUM` over an
# indexed column rather than a stored total, because a stored total is a second copy of the
# truth that has to be kept in step with every delete.
class Rating < ApplicationRecord
  LIKE = 1
  DISLIKE = -1
  SCORES = [ LIKE, DISLIKE ].freeze

  # `rateable` is the thing reacted to; `author` is who reacted. Different names because the
  # two are different kinds of thing, and the code reads worse when they are not.
  belongs_to :rateable, polymorphic: true
  belongs_to :author, class_name: "User"

  validates :score, inclusion: { in: SCORES }
  validates :author_id, uniqueness: { scope: [ :rateable_type, :rateable_id ],
    message: "has already reacted to this" }
  validate :not_your_own

  scope :likes, -> { where(score: LIKE) }
  scope :dislikes, -> { where(score: DISLIKE) }

  private
    # Nobody votes on their own thing. Everything else about a post is its owner's already;
    # the score is the one number on it that has to come from other people.
    def not_your_own
      return if rateable.nil? || author_id.nil?

      owner = rateable.respond_to?(:owner) ? rateable.owner : nil
      return if owner.nil? || owner.id != author_id

      errors.add(:author, "cannot react to their own post")
    end
end
