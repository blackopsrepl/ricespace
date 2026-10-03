# frozen_string_literal: true

# The published layouts a page can wear.
#
# Applying one adds its rules to the page's own stylesheet rather than replacing
# what the owner wrote: a layout is a starting point, and the era's pages were
# layered — paste a layout, then paste your own rules over the parts you want
# different. The page's own rules come last, so they win.
class LayoutsController < ApplicationController
  def index
    @layouts = Layout.all
  end

  def show
    @layout = Layout.find(params[:id])
    @profile = signed_in? ? current_user.profile : nil
    @preview_user = preview_user
  end

  def apply
    return redirect_to layouts_path, alert: "Sign in to use a layout." unless signed_in?

    layout = Layout.find(params[:id])
    profile = current_user.profile
    profile.update!(document: LayoutApplication.new(profile, layout).document)

    redirect_to profile_path(current_user), notice: "Applied “#{layout.name}”."
  end

  private
    # A page to render the layout against, so the preview shows the layout rather
    # than a blank document. The signed-in owner sees their own parts.
    def preview_user
      signed_in? ? current_user : nil
    end
end
