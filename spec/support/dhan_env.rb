# frozen_string_literal: true

# Dhan credentials the SDK and Dhan::TokenManager read straight from ENV.
#
# `Dhan::TokenManager` uses a strict `ENV.fetch('DHAN_CLIENT_ID')`, so without
# these any spec that reaches a broker call fails with a bare KeyError long
# before VCR gets a chance to replay the cassette. The values only need to be
# present, not real — VCR serves the HTTP and filters these out of recordings.
# Every key here is read with a strict `ENV.fetch(key)` somewhere in the app,
# so a missing one raises KeyError rather than degrading.
RSpec.configure do |config|
  config.before(:suite) do
    {
      'DHAN_CLIENT_ID' => 'test-client-id',
      'CLIENT_ID' => 'test-client-id',
      'ACCESS_TOKEN' => 'test-access-token',
      'DHAN_ACCESS_TOKEN' => 'test-access-token',
      'DHAN_PIN' => '1234',
      'DHAN_TOTP_SECRET' => 'JBSWY3DPEHPK3PXP', # valid base32, never used live
      'OPENAI_API_KEY' => 'test-openai-key',
      'TELEGRAM_BOT_TOKEN' => 'test-telegram-token',
      'TELEGRAM_CHAT_ID' => '0'
    }.each { |key, value| ENV[key] ||= value }

    # config/initializers/dhanhq.rb already ran when rails_helper booted the
    # environment, so setting ENV alone is too late — the SDK would still
    # refuse DATA API calls with "client_id is required". Apply it directly.
    DhanHQ.configuration.client_id ||= ENV.fetch('DHAN_CLIENT_ID')
  end
end
