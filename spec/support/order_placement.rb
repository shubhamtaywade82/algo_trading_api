# frozen_string_literal: true

# Live order placement needs two switches on: this app's PLACE_ORDER gate and
# the DhanHQ SDK's own LIVE_TRADING gate (required since gem 2.7). A spec that
# exercises the placement path has to set both, or Orders::Gateway returns its
# dry-run result and nothing reaches the stubbed broker.
#
# Tag an example or group with `:with_order_placement` to enable both for its
# duration and restore the previous values afterwards.
RSpec.configure do |config|
  config.around(:each, :with_order_placement) do |example|
    original = ENV.to_h.slice('PLACE_ORDER', 'LIVE_TRADING')
    ENV['PLACE_ORDER'] = 'true'
    ENV['LIVE_TRADING'] = 'true'
    example.run
  ensure
    %w[PLACE_ORDER LIVE_TRADING].each { |key| ENV[key] = original[key] }
  end
end
