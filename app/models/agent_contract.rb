# frozen_string_literal: true

# The contract a coding agent codes against, written once in docs/ and served
# two ways: raw markdown for the agent to fetch, and a page for its owner to
# read. One copy, so the promise and the documentation cannot drift apart.
class AgentContract
  FILENAME = "agent-contract.md"

  def self.path
    Rails.root.join("docs", FILENAME)
  end

  def self.markdown
    path.read
  end
end
