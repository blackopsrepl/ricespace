# frozen_string_literal: true

# What it means for something to be posted.
#
# A page, a rice, a shot of it, a build, a photo of that build, a demo, a link, a block of
# text — these are the things a person puts on this site, and they are all the same kind of
# thing: they can be reacted to and they can be written on. This concern is that sameness, in
# one place, so the next kind of posted thing is a line in a model rather than a new table, a
# new controller and a new set of views.
#
# It also carries the ownership rule, because every one of these belongs to an account and
# every feature that needs to ask "is this mine?" needs the same answer.
module Reactable
  extend ActiveSupport::Concern

  included do
    # The reactions on this thing, and the wall under it.
    has_many :reactions, as: :rateable, dependent: :destroy, class_name: "Rating"
    has_many :comments, as: :commentable, dependent: :destroy
  end

  # The account this belongs to.
  #
  # A page belongs to itself — it *is* an account. Most other things belong to an account
  # directly. A shot belongs to a rice and a photo to a build, so theirs is their parent's.
  # That is why this asks rather than assumes.
  def owner
    return self if is_a?(User)
    return user if respond_to?(:user)

    parent = respond_to?(:showcase) ? showcase : (respond_to?(:build) ? build : nil)
    parent&.owner
  end

  # The score of this one thing: likes minus dislikes.
  def score
    reactions.sum(:score)
  end

  def likes
    reactions.where(score: Rating::LIKE).count
  end

  def dislikes
    reactions.where(score: Rating::DISLIKE).count
  end

  # Everything anybody wrote about it, newest first.
  def wall
    comments.includes(:author).recent_first
  end

  # What this thing is called, for a sentence that has to name it without linking to it.
  def reactable_label
    self.class.name.underscore.humanize.downcase
  end
end
