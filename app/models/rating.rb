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

# One account's opinion of one page.
#
# A rating is a single like or dislike, not a count, and there is one per pair: a person
# rates a page once and changing their mind edits that rating. That is what keeps the
# number meaning "how many people said yes" instead of "how many times the button was
# pressed", which is the difference between an old-school popularity score and a metric.
#
# The page's score is calculated from these rows rather than kept in a column. A stored
# total is a second copy of the truth that has to be kept in step with every delete, and
# this one is a `SUM` over an indexed column.
class Rating < ApplicationRecord
  LIKE = 1
  DISLIKE = -1
  SCORES = [ LIKE, DISLIKE ].freeze

  belongs_to :user                                     # the page being rated
  belongs_to :author, class_name: "User"               # who rated it

  validates :score, inclusion: { in: SCORES }
  validates :author_id, uniqueness: { scope: :user_id, message: "has already rated this page" }
  validate :not_own_page

  scope :likes, -> { where(score: LIKE) }
  scope :dislikes, -> { where(score: DISLIKE) }

  private
    # A page's own owner does not vote on it. Everything else about a page is theirs
    # already; the score is the one number on it that has to come from other people.
    def not_own_page
      return if user_id.nil? || author_id.nil?
      return unless user_id == author_id

      errors.add(:author, "cannot rate their own page")
    end
end
