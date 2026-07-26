# frozen_string_literal: true

# Ensure job specs that depend on Dhan have a valid token so ensure_dhan_token! passes.
# Skip when example is tagged :no_dhan_token (e.g. DhanAccessToken specs that test expiry).
RSpec.configure do |config|
  config.before do |example|
    next if example.metadata[:no_dhan_token]
    next if DhanAccessToken.exists?

    DhanAccessToken.create!(
      access_token: 'test-token',
      expires_at: 1.day.from_now
    )
  end

  # The SDK's access_token_provider calls Dhan::TokenManager.current_token! on
  # every request. When the seeded row is missing — e.g. DatabaseCleaner has
  # truncated between hooks — it falls through to a real TOTP handshake against
  # auth.dhan.co, which VCR then rejects as an unhandled request. Cassettes for
  # business endpoints should not have to carry the auth exchange, so stub it.
  #
  # TokenManager's own specs exercise the real path and are excluded.
  config.before do |example|
    next if example.metadata[:no_dhan_token]
    next if example.metadata[:file_path].to_s.include?('token_manager_spec')

    # force_refresh! is included because on_token_expired routes there, which
    # would also reach auth.dhan.co.
    allow(Dhan::TokenManager).to receive_messages(
      current_token!: 'test-token',
      force_refresh!: 'test-token'
    )
  end
end
