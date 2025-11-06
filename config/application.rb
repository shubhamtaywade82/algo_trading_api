# frozen_string_literal: true

require_relative 'boot'

require 'rails'
# Pick the frameworks you want:
require 'active_model/railtie'
require 'active_job/railtie'
require 'active_record/railtie'
require 'active_storage/engine'
require 'action_controller/railtie'
require 'action_mailer/railtie'
require 'action_mailbox/engine'
require 'action_text/engine'
require 'action_view/railtie'
require 'action_cable/engine'
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module AlgoTradingApp
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # Exclude 'dhanhq' from autoloading as it's a backwards-compatibility layer
    # that defines Dhanhq::API (not Dhanhq::Api as Zeitwerk expects)
    config.autoload_lib(ignore: %w[assets tasks dhanhq])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    config.hosts << /.*\.ngrok-free\.app/
    config.hosts << 'localhost'
    config.hosts << /.*/

    config.time_zone = 'Asia/Kolkata'
    config.active_record.default_timezone = :local

    # ─────────────────────────────────────────────
    # Inline background loops (only for local / dev)
    # ─────────────────────────────────────────────
    unless ENV['RENDER_ROLE']
      config.after_initialize do
        # Start Feed + Manager loops only if enabled via ENV
        if ENV['ENABLE_FEED_LISTENER'] == 'true' || ENV['ENABLE_POSITION_MANAGER'] == 'true'
          # require Rails.root.join('lib/feed/runner')
          # Feed::Runner.start
          Feed::Runner.start_feed_listener
        end

        # Optional: Rebuild crontab for development
        system('bundle exec whenever --update-crontab') if Rails.env.development?
      end
    end
  end
end
