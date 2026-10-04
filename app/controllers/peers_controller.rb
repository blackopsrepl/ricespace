# frozen_string_literal: true

# This node's view of the network: the feeds it holds, what verified, and the
# sync that pulls follows up to date. Local only in spirit — it shows the
# machine's own replica state, not a global directory.
class PeersController < ApplicationController
  before_action :require_authentication, only: [ :sync, :add, :react, :comment ]

  # Every held feed: petname, short id, seq, health. The directory this node
  # computes from what it actually holds — not a registry, a replica list.
  def index
    @peers = Peer.followed.order(updated_at: :desc)
    @own = Peer.own
  end

  # One replicated page, read-only, rendered through the same cleaners as a
  # local page. A lazy renderer is how XSS ships; this one is not lazy.
  def show
    @peer = Peer.followed.find_by!(pubkey: params[:pubkey])
    return render plain: "This feed is closed.", status: :gone if @peer.deleted?
    return render plain: "This feed is compromised.", status: :conflict if @peer.compromised?

    document = @peer.latest_document
    return render plain: "no page replicated for #{@peer.short_id}", status: :not_found if document.nil?

    @rendered = ProfileMarkup.render(document)
    @rice = @peer.latest_rice
    @lists = @peer.latest_lists
    @score = @peer.score
    @compromised = @peer.compromised?
    @deleted = @peer.deleted?
    page_record = @peer.records.where(kind: "page").order(seq: :desc).first
    @wall = page_record ? @peer.comments_on(page_record.record_hash) : []
  end

  # Follow somebody: store the petname + address, so the next sync pulls them.
  def add
    pubkey = params[:pubkey].to_s.strip.downcase
    unless pubkey.match?(Peer::HEX)
      return redirect_to peers_path, alert: "That is not an account — a key is 64 hex characters."
    end

    peer = Peer.find_or_initialize_by(pubkey: pubkey)
    peer.petname = params[:petname].to_s.strip.presence || peer.petname || pubkey[0, 12]
    peer.followed = true
    peer.save!

    redirect_to peers_path, notice: "Following #{peer.petname} [#{pubkey[0, 4]}..#{pubkey[-4, 4]}]."
  end

  # Pull every followed feed up to date from the local store (written by
  # `ricespace peer sync` on this machine). The CLI moves bytes; this verifies
  # them into rows the pages render from.
  def sync
    result = PeerSync.import_store(RiceSpace::P2p::Feed.root)
    message = "Imported #{result[:imported]} records."
    message += " Compromised: #{result[:compromised].join(", ")}." if result[:compromised].any?
    redirect_to peers_path, notice: message
  end

  # Reacting to a replicated page. Same toggle as a local page — press what you
  # pressed and it is withdrawn — but signed into your own feed as a record,
  # not written as a Rating row on somebody else's table.
  def react
    peer = Peer.find_by!(pubkey: params[:pubkey])
    opinion = params[:opinion].to_s
    unless %w[like dislike].include?(opinion)
      return redirect_to peer_path(peer.pubkey), alert: "That is not a reaction."
    end

    unless PeerWrite.authorized?(current_user)
      return redirect_to peer_path(peer.pubkey),
        alert: "This node may not sign for your account yet — authorise its device key first."
    end

    page_record = peer.records.where(kind: "page").order(seq: :desc).first
    if page_record.nil?
      return redirect_to peer_path(peer.pubkey), alert: "That page has nothing to react to yet."
    end

    PeerWrite.react(user: current_user, peer: peer, opinion: opinion,
      target_hash: page_record.record_hash)
    redirect_to peer_path(peer.pubkey), notice: "#{opinion.capitalize}d #{peer.petname.presence || peer.short_id}."
  rescue RiceSpace::P2p::Error => error
    redirect_to peer_path(params[:pubkey]), alert: error.message
  end

  # Writing on a replicated page's wall. Signed into your own feed; the owner's
  # node verifies it like any other record.
  def comment
    peer = Peer.find_by!(pubkey: params[:pubkey])
    body = params.require(:comment).permit(:body)[:body].to_s.strip
    if body.empty? || body.length > 1_000
      return redirect_to peer_path(peer.pubkey), alert: "A comment is words — up to 1,000 characters."
    end

    unless PeerWrite.authorized?(current_user)
      return redirect_to peer_path(peer.pubkey),
        alert: "This node may not sign for your account yet — authorise its device key first."
    end

    page_record = peer.records.where(kind: "page").order(seq: :desc).first
    if page_record.nil?
      return redirect_to peer_path(peer.pubkey), alert: "That page has no wall yet."
    end

    PeerWrite.comment(user: current_user, parent_hash: page_record.record_hash, text: body)
    redirect_to peer_path(peer.pubkey), notice: "Comment left."
  rescue RiceSpace::P2p::Error => error
    redirect_to peer_path(params[:pubkey]), alert: error.message
  end
end
