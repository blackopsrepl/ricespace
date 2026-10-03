# frozen_string_literal: true

# The videos and streams on a page: add a link, take it off. The link is read here and
# what is read (platform and id) is stored; the URL is never stored as the source of an
# embed, so a page cannot be made to frame somewhere its owner typed.
class StreamLinksController < ApplicationController
  before_action :require_authentication

  def create
    link = current_user.stream_links.build(url: params.dig(:stream_link, :url),
      title: params.dig(:stream_link, :title))

    if link.save
      redirect_to studio_path, notice: "#{link.platform_label} added to your page."
    else
      redirect_to studio_path, alert: link.errors.full_messages.to_sentence
    end
  end

  def destroy
    current_user.stream_links.find(params[:id]).destroy!

    redirect_to studio_path, notice: "Removed from your page."
  end
end
