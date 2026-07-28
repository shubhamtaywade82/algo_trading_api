# frozen_string_literal: true

# Optional in-process start for the crypto SMC scanner.
#
# The supported way to run the scanner is a dedicated process:
#
#   bundle exec rake crypto:stream
#
# This app is deployed as a single Render web service with no cron service and
# `:async` for Active Job, so there is nowhere else for a long-running listener
# to live. CRYPTO_SMC_AUTOSTART=true starts one inside the web process, in the
# same spirit as the token-refresh thread that already runs there.
#
# Two caveats, both deliberate rather than bugs:
#
#   * Puma runs WEB_CONCURRENCY workers, and each one boots this file, so a
#     multi-worker deploy opens a socket per worker. They cannot double-alert —
#     AlertDispatcher's shared cooldown is keyed on the setup, not the process —
#     but they do duplicate the Binance traffic. Prefer the dedicated process.
#   * Nothing starts unless CRYPTO_SMC_ENABLED is also true, so this file is
#     inert on every existing deployment.
Rails.application.config.after_initialize do
  next unless ENV.fetch('CRYPTO_SMC_AUTOSTART', 'false').to_s.downcase == 'true'
  next unless Crypto::Config.enabled?
  next if Rails.env.test?
  # Rake tasks, migrations and consoles have no business holding a socket open.
  next if defined?(Rails::Console) || File.basename($PROGRAM_NAME) == 'rake'

  Thread.new do
    Thread.current.name = 'crypto-smc-stream'
    Thread.current.abort_on_exception = false

    begin
      Rails.logger.info('[Crypto] autostarting SMC kline stream')
      Crypto::Binance::KlineStream.new.run
    rescue StandardError => e
      Rails.logger.error("[Crypto] kline stream thread died: #{e.class} - #{e.message}")
    end
  end
end
