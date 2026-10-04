# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/ricespace"

# Bencode and the BEP44 wire bytes: our encoder must produce exactly the
# bytes the spec's test vectors sign, or no Mainline node will verify us.
class NetBep44Test < Minitest::Test
  include RiceSpace::P2p::Net

  def test_bencode_round_trips_a_krpc_query
    value = { "t" => "aa", "y" => "q", "q" => "ping",
      "a" => { "id" => "abcdefghij0123456789" } }

    assert_equal value, Bencode.decode(Bencode.encode(value))
  end

  def test_bencode_sorts_dict_keys
    assert_equal "d1:a1:x1:b1:ye", Bencode.encode({ "b" => "y", "a" => "x" })
  end

  def test_bencode_keeps_binary_strings_binary
    raw = (0..255).map(&:chr).join.b
    decoded = Bencode.decode(Bencode.encode([ raw ]))

    assert_equal raw, decoded.first
    assert_equal Encoding::BINARY, decoded.first.encoding
  end

  def test_bencode_refuses_truncation_and_garbage
    assert_raises(RiceSpace::P2p::Error) { Bencode.decode("i12") }
    assert_raises(RiceSpace::P2p::Error) { Bencode.decode("x") }
    assert_raises(RiceSpace::P2p::Error) { Bencode.decode("4:ab") }
  end

  def test_bep44_signature_buffer_test_vector_1
    # BEP44 test 1: value "Hello World!", seq 1, no salt.
    assert_equal "3:seqi1e1:v12:Hello World!", Dht.signed_bytes(seq: 1, v: "Hello World!")
  end

  def test_bep44_test_vector_1_verifies
    k = "77ff84905a91936367c01360803104f92432fcd904a43511876df5cdf3e7e548"
    sig = "305ac8aeb6c9c151fa120f120ea2cfb923564e11552d06a5d856091e5e853cff" \
      "1260d3f39e4999684aa92eb73ffd136e6f4f3ecbfda0ce53a1608ecd7ae21f01"

    assert_equal "4a533d47ec9c7d95b1ad75f576cffc641853b750", Dht.target_for(k)
    assert RiceSpace::P2p::Keys.verify(k, sig, Dht.signed_bytes(seq: 1, v: "Hello World!"))
  end

  def test_bep44_test_vector_2_salted
    k = "77ff84905a91936367c01360803104f92432fcd904a43511876df5cdf3e7e548"
    sig = "6834284b6b24c3204eb2fea824d82f88883a3d95e8b4a21b8c0ded553d17d17d" \
      "df9a8a7104b1258f30bed3787e6cb896fca78c58f8e03b5f18f14951a87d9a08"

    assert_equal "4:salt6:foobar3:seqi1e1:v12:Hello World!",
      Dht.signed_bytes(seq: 1, v: "Hello World!", salt: "foobar")
    assert_equal "411eba73b6f087ca51a3795d9c8c938d365e32c1", Dht.target_for(k, salt: "foobar")
    assert RiceSpace::P2p::Keys.verify(k, sig,
      Dht.signed_bytes(seq: 1, v: "Hello World!", salt: "foobar"))
  end

  def test_bep44_immutable_target_is_sha1_of_bencoded_value
    assert_equal "e5f96f6f38320f0f33959cb4d3d656452117aadb",
      Digest::SHA1.hexdigest(Bencode.encode("Hello World!"))
  end

  def test_krpc_get_peers_example_encodes_like_the_spec
    # BEP5's own example packet, byte-identical.
    query = { "t" => "aa", "y" => "q", "q" => "get_peers",
      "a" => { "id" => "abcdefghij0123456789", "info_hash" => "mnopqrstuvwxyz123456" } }

    assert_equal "d1:ad2:id20:abcdefghij01234567899:info_hash20:mnopqrstuvwxyz123456" \
      "e1:q9:get_peers1:t2:aa1:y1:qe", Bencode.encode(query)
  end
end
