# frozen_string_literal: true

# The hardware on a page: a physical build, a rack, a cooling setup, a closet.
#
# Its own category rather than another showcase, because the picture is the evidence and
# the facts are different ones — what is in it, and how it is cooled — and because a page
# is allowed more than one of these in a way it is not allowed more than one rice.
#
# Same structure as the showcase on purpose: photos in their own table, facts as columns,
# details as the owner's own markup. A page with a rice and a rack should read as one page
# designed once, not two features bolted together.
class Build < ApplicationRecord
  MAX_TITLE_LENGTH = 120
  MAX_LINE_LENGTH = 80
  MAX_DETAILS_LENGTH = 20_000

  # What kind of physical thing this is. A vocabulary, not free text: "rack" is worth
  # being able to read off a list.
  KINDS = {
    "desktop" => "desktop build",
    "server" => "server",
    "rack" => "rack",
    "homelab" => "homelab",
    "cooling" => "cooling",
    "storage" => "storage",
    "laptop" => "laptop",
    "peripherals" => "peripherals",
    "network" => "network",
    "other" => "other"
  }.freeze

  belongs_to :user
  has_many :photos, -> { order(:position, :id) }, class_name: "BuildPhoto",
    dependent: :destroy, inverse_of: :build

  normalizes :title, with: ->(value) { value.to_s.strip }
  normalizes :summary, with: ->(value) { value.to_s.strip }
  normalizes :specs, with: ->(value) { value.to_s.strip }
  normalizes :cooling, with: ->(value) { value.to_s.strip }
  normalizes :kind, with: ->(value) { value.to_s.strip }

  validates :title, presence: true, length: { maximum: MAX_TITLE_LENGTH }
  validates :summary, length: { maximum: 200 }, allow_blank: true
  validates :details, length: { maximum: MAX_DETAILS_LENGTH }
  validates :specs, :cooling, length: { maximum: MAX_LINE_LENGTH }, allow_blank: true
  validates :kind, inclusion: { in: KINDS.keys }, allow_blank: true

  scope :in_order, -> { order(created_at: :desc) }

  def kind_label
    KINDS[kind]
  end

  # The picture the page leads with, or nil.
  def cover
    photos.find { |photo| photo.image.attached? }
  end

  # The facts that have been filled in, in the order they are shown.
  def facts
    [ [ "kind", kind_label ], [ "specs", specs.presence ], [ "cooling", cooling.presence ] ]
      .select { |_label, value| value.present? }
  end

  def rendered_details
    ProfileMarkup.render(details).html
  end
end
