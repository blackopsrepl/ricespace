# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Importmap vulnerability audit", "bin/importmap audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  step "Tests: Rails", "bin/rails test"
  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"
  # The client. It is Ruby in this repository, so it is linted by the same RuboCop and
  # tested by the same `make check` as the site — which is the reason it is Ruby.
  step "Tests: CLI", "ruby -Icli/lib cli/test/ricespace_test.rb"
  step "Tests: P2P", "ruby -Icli/lib cli/test/p2p_test.rb"
  step "Tests: Peer address", "ruby -Icli/lib cli/test/peer_address_test.rb"
  step "Tests: Net BEP44", "ruby -Icli/lib cli/test/net_bep44_test.rb"
  step "Tests: Net endpoint", "ruby -Icli/lib cli/test/net_endpoint_test.rb"
  step "Tests: Net NAT", "ruby -Icli/lib cli/test/net_nat_test.rb"
  step "Tests: Net DHT", "ruby -Icli/lib cli/test/net_dht_test.rb"
  step "Tests: Net relay", "ruby -Icli/lib cli/test/net_relay_test.rb"
  step "Tests: Net discovery", "ruby -Icli/lib cli/test/net_discovery_test.rb"
  step "Tests: Net rendezvous", "ruby -Icli/lib cli/test/net_rendezvous_test.rb"
  step "Tests: Net CLI", "ruby -Icli/lib cli/test/net_cli_test.rb"

  # The pictures the README shows. They are generated, so the script that generates them is
  # part of the product, and the framework wrappers beside it are not: a syntax error in
  # `bin/shots` is a README nobody can update, and RuboCop's own discovery does not reach it.
  step "Lint: bin scripts", "bin/rubocop bin/shots"

  # Optional: Run system tests
  # step "Tests: System", "bin/rails test:system"

  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
