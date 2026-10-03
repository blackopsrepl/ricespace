# frozen_string_literal: true

# A local preview of a folder, rendered by the site's own code.
#
# `ricespace preview` hands this controller a folder and asks it to draw the page that
# folder would become. The point of doing it here rather than in the CLI is that the rules
# are not reimplemented: the markup goes through ProfileMarkup and the stylesheet through
# PageCss, exactly as a real page does. A preview that guesses which of your tags survive
# is worse than no preview, because it is confidently wrong.
#
# It is local-only and reads nothing from the database: the folder is the whole input.
class PreviewController < ApplicationController
  # A folder is trusted because it is on the machine of the person running it, so this is
  # not a security boundary — but it is still bounded, in case a request arrives from
  # somewhere unexpected.
  ALLOWED_ROOT = Rails.root.join("tmp", "preview").freeze

  # The files a folder may hold.
  PAGE = "page.html"
  RICE = "rice.json"

  def show
    @folder = preview_root

    return render plain: "ricespace preview: no folder at #{@folder}", status: :not_found unless @folder.directory?

    @username = params[:username].to_s.presence || "you"
    @rendered = ProfileMarkup.render(read_page)
    @rice = read_json(RICE) || {}
    @blurbs = read_list("blurbs.json")
    @demos = read_list("demos.json")
    @builds = read_list("builds.json")
    @links = read_list("links.json")
    @friends = read_list("friends.json")

    render :show, layout: "preview"
  end

  private
    # The folder is chosen by *name* from the directories that already exist, and the requested
    # name is only ever compared, never joined onto a path. That matters: a request that
    # contributes to a file name is how a preview route becomes a way to read arbitrary files,
    # and the defence that cannot be forgotten is to not build the path from it at all.
    def preview_root
      wanted = File.basename(params[:folder].to_s)
      return ALLOWED_ROOT if wanted.blank? || wanted == "." || wanted == ".."

      found = ALLOWED_ROOT.children.find { |child| child.directory? && child.basename.to_s == wanted }

      # A name that matches nothing resolves to a directory that is not there, which the
      # action reports as "no folder" — the same answer, without ever touching a bad path.
      found || ALLOWED_ROOT.join("__no_such_folder__")
    end

    def read_page
      file = @folder.join(PAGE)
      return "" unless file.file?

      file.read(Profile::MAX_DOCUMENT_LENGTH)
    end

    # The rice and the lists as JSON, in the same shapes the API speaks, so a folder is the
    # API's own language written down rather than a second format to keep in step.
    def read_json(name)
      file = File.join(@folder, name)
      return nil unless File.file?(file)

      JSON.parse(File.read(file))
    rescue JSON::ParserError
      nil
    end

    def read_list(name)
      Array(read_json(name))
    end
end
