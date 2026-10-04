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

  # Link this account to its P2P feed: paste the master public key from
  # `ricespace identity show`, and this node renders that feed as yours —
  # publishing your writes into it and signing your remote reactions as you.
  def link_feed
    key = params.require(:user).permit(:pubkey)[:pubkey].to_s.strip.downcase
    if key.match?(Peer::HEX) || key.empty?
      current_user.update!(pubkey: key.presence)
      PeerWrite.own_feed(current_user) if key.present?
      redirect_to studio_path, notice: key.present? ?
        "Linked — this node now speaks as #{RiceSpace::P2p::Canonical.short_id(key)}." :
        "Unlinked — this account is local-only again."
    else
      redirect_to studio_path, alert: "That is not a key — paste the 64 hex characters from `ricespace identity show`."
    end
  rescue ActiveRecord::RecordInvalid => error
    redirect_to studio_path, alert: error.record.errors.full_messages.to_sentence
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
