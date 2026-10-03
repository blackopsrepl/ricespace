# frozen_string_literal: true

# The showcase: the rice.
#
# This is the part of a page that is the point. Everything else on a profile — the
# markup, the friends, the song — is a page; this is what the page is *showing*: a
# screenshot of a desktop somebody built and what went into it.
#
# It is a model rather than free markup in the page's document for one reason: a rice is
# a set of facts (the machine, the window manager, the bar, the terminal, the font, the
# theme) and a set of pictures, and facts can be listed, filtered and copied. Free markup
# can only be looked at.
class Showcase < ApplicationRecord
  MAX_DETAILS_LENGTH = 20_000
  MAX_LINE_LENGTH = 80

  # The setup facts a rice is described by. Each is a name, not a paragraph.
  FACTS = {
    hardware: "hardware",
    window_manager: "window manager",
    bar: "bar",
    terminal: "terminal",
    font: "font",
    theme: "theme"
  }.freeze

  belongs_to :user
  has_many :shots, -> { order(:position, :id) }, class_name: "ShowcaseShot",
    dependent: :destroy, inverse_of: :showcase

  # One showcase per account, enforced at the database by a unique index — and here, so
  # the failure is a validation error rather than a raised constraint.
  validates :user_id, uniqueness: true

  normalizes :title, with: ->(value) { value.to_s.strip }
  normalizes :summary, with: ->(value) { value.to_s.strip }
  FACTS.each_key { |fact| normalizes fact, with: ->(value) { value.to_s.strip } }

  validates :title, length: { maximum: MAX_LINE_LENGTH }, allow_blank: true
  validates :summary, length: { maximum: 200 }, allow_blank: true
  validates :details, length: { maximum: MAX_DETAILS_LENGTH }
  FACTS.each_key { |fact| validates fact, length: { maximum: MAX_LINE_LENGTH }, allow_blank: true }

  # The facts that have been filled in, in the order they are shown.
  def facts
    FACTS.filter_map do |fact, label|
      value = public_send(fact)
      [ label, value ] if value.present?
    end
  end

  # The details as markup: the same allowlist as a page's markup, because this is
  # markup the owner wrote and it reaches the same page.
  def rendered_details
    ProfileMarkup.render(details).html
  end

  # The picture the page leads with, or nil.
  def cover
    shots.find { |shot| shot.image.attached? }
  end

  # Whether there is anything to show. Deliberately not named `present?`: overriding it
  # changes what `blank?` means for this model, and Active Record asks.
  def filled?
    title.present? || summary.present? || details.present? || facts.any? || cover
  end
end
