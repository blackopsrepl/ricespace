# frozen_string_literal: true

# A layout: a stylesheet somebody wrote for a profile page, published so others can
# paste it onto theirs.
#
# The era's layouts were exactly this — a blob of CSS passed around and copied into
# a profile — and the reason to have them here is that writing CSS is a skill and
# having a page shouldn't require it. Applying one replaces the page's stylesheet
# and leaves its content alone, which is what "using a layout" meant.
#
# A layout's css is written by us and rendered as-is, like a view. It becomes user
# content the moment it is applied to a page, and it is cleaned there, on render,
# by PageCss like any other stylesheet.
class Layout
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :slug, :string
  attribute :name, :string
  attribute :author, :string
  attribute :description, :string
  attribute :css, :string

  # The layouts that ship with the site, held in a directory of .css files so a new
  # one is a file and a commit rather than a row somebody has to seed into every
  # environment. The name and author come from the file's first two comment lines.
  DIRECTORY = Rails.root.join("app", "layouts")

  class NotFound < StandardError; end

  class << self
    # Every layout, in a stable order.
    def all
      @all ||= load_all
    end

    def find(slug)
      all.find { |layout| layout.slug == slug } or raise NotFound, slug
    end

    # Reload from disk. Called by tests, which write layouts into the directory and
    # need to see them without restarting the process.
    def reload!
      @all = nil
      all
    end

    private
      def load_all
        Dir[DIRECTORY.join("*.css")].sort.map { |path| from_file(path) }
      end

      def from_file(path)
        source = File.read(path)
        meta = source[/\A\/\*(.*?)\*\//m, 1].to_s

        new(
          slug: File.basename(path, ".css"),
          # Metadata lines are indented in the files, so the anchors allow leading
          # space rather than requiring the label at column zero.
          name: meta[/^\s*name:\s*(.+)$/i, 1].to_s.strip,
          author: meta[/^\s*author:\s*(.+)$/i, 1].to_s.strip,
          description: meta[/^\s*description:\s*(.+)$/i, 1].to_s.strip,
          css: source.sub(/\A\/\*.*?\*\/\s*/m, "").strip
        )
      end
  end

  def to_param
    slug
  end
end
