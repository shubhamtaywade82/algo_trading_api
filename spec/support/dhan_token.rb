# frozen_string_literal: true

# Ensure job specs that depend on Dhan have a valid token so ensure_dhan_token! passes.
# Skip when example is tagged :no_dhan_token (e.g. DhanAccessToken specs that test expiry).
RSpec.configure do |config|
  config.before do |example|
    next if example.metadata[:no_dhan_token]
    next if DhanAccessToken.valid?

    DhanAccessToken.create!(
      access_token: 'test-token',
      expires_at: 1.day.from_now
    )
  end
end
