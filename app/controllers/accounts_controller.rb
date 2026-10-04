# frozen_string_literal: true

# The signed-in owner's own account: the details shown beside their picture, and
# closing the account.
#
# Deleting is a button on the studio after a deliberate confirmation rather than a
# link in a menu. It is the owner's own account or nothing: there is no path here
# to delete somebody else's, and the site's own account cannot be closed because
# every page on the site lists it.
class AccountsController < ApplicationController
  before_action :require_authentication

  def update
    if current_user.update(account_params)
      redirect_to studio_path, notice: "Details saved."
    else
      redirect_to studio_path, alert: current_user.errors.full_messages.to_sentence
    end
  end

  def link_feed
    attributes = params.require(:user).permit(:pubkey, :proof)
    key = attributes[:pubkey].to_s
    if key.empty?
      FeedLink.unlink!(current_user)
      return redirect_to studio_path, notice: "Unlinked — this account is local-only again."
    end
    raise RiceSpace::P2p::Error, "A feed key is exactly 64 lowercase hex characters." unless key.match?(Peer::HEX)

    challenge = session.delete(:feed_challenge)
    issued = session.delete(:feed_challenge_at).to_i
    unless challenge.present? && issued > 10.minutes.ago.to_i && issued <= Time.current.to_i
      raise RiceSpace::P2p::Error, "Open the studio for a fresh ownership challenge."
    end
    FeedLink.link!(current_user, key, attributes[:proof].to_s, challenge)
    redirect_to studio_path, notice: "Linked — verified feed imported; editor refresh uses draft protection."
  rescue RiceSpace::P2p::Error, ActiveRecord::ActiveRecordError, SystemCallError => error
    redirect_to studio_path, alert: error.is_a?(RiceSpace::P2p::Error) ? error.message : "Feed linking failed; nothing was linked."
  end

  def destroy
    if current_user.admin?
      return redirect_to studio_path, alert: "The site's own account cannot be closed."
    end

    username = current_user.username
    # A linked feed closes on the network too: tombstone, so honest peers drop
    # the page. Local rows go with `close!` as before.
    PeerWrite.goodbye(current_user) if current_user.pubkey.present?
    current_user.close!
    reset_session

    redirect_to root_path, notice: "The page @#{username} is gone, with everything on it."
  end

  private
    def account_params
      params.require(:user).permit(:name, :greeting, :mood, :headline)
    end
end
