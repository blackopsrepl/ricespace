# frozen_string_literal: true

require "test_helper"

class AgentTokenTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(username: "vittorio", email_address: "vittorio@example.com", password: "correct horse battery")
  end

  test "issuing a token discloses it once and stores only a digest" do
    record = AgentToken.issue(user: @user, name: "claude code")

    assert_match AgentToken::TOKEN_FORMAT, record.plaintext
    assert_nil AgentToken.find_by(token_digest: record.plaintext)
    assert_equal record, AgentToken.find_by(token_digest: AgentToken.digest(record.plaintext))
    assert_nil AgentToken.find(record.id).plaintext
  end

  test "tokens are unguessable and distinct" do
    tokens = 5.times.map { AgentToken.issue(user: @user, name: "agent").plaintext }

    assert_equal tokens.size, tokens.uniq.size
    assert_operator tokens.first.length, :>=, 32
  end

  test "authenticating with an issued token returns its owner's record and records the use" do
    record = AgentToken.issue(user: @user, name: "claude code")
    record.update_column(:last_used_at, nil)

    assert_equal record, AgentToken.authenticate(record.plaintext)
    assert_not_nil record.reload.last_used_at
  end

  test "a malformed or unknown token authenticates as nothing" do
    AgentToken.issue(user: @user, name: "claude code")

    candidates = [ nil, "", "rs_", "nope", "rs_#{'a' * 48}", AgentToken.digest("rs_#{'a' * 48}") ]

    candidates.each do |candidate|
      assert_nil AgentToken.authenticate(candidate), "expected #{candidate.inspect} to be refused"
    end
  end

  test "a token belongs to one account" do
    assert_not AgentToken.new(name: "agent").valid?
  end

  test "a token needs a name so its owner can tell them apart" do
    assert_not @user.agent_tokens.new(name: "").valid?
  end
end
