# frozen_string_literal: true

module Crypto
  # Scheduled sweep: analyse every configured pair and alert on what qualifies.
  #
  # Deliberately **not** an `ApplicationJob`. That base class runs
  # `ensure_dhan_token!` before every perform and re-raises when the token
  # cannot be minted, which would take the crypto scanner down every time the
  # Dhan session lapsed — an unrelated broker, an unrelated market, and one
  # that is closed at most of the hours this job runs. Binance market data
  # needs no credential at all.
  #
  # Retries are off for the same reason a stale scan is worse than a missed
  # one: by the time a retry lands, the 5m candle that triggered it has been
  # replaced, and an alert on it would describe a chart that no longer exists.
  # The next scheduled run is the retry.
  # rubocop:disable Rails/ApplicationJob -- see the note above: ApplicationJob
  # mints a DhanHQ token before every perform and re-raises on failure, which
  # this job must not depend on.
  class SmcScanJob < ActiveJob::Base
    # rubocop:enable Rails/ApplicationJob
    queue_as :default

    discard_on StandardError do |job, error|
      Rails.logger.error("[Crypto::SmcScanJob] discarded: #{error.class} - #{error.message}")
      Rails.logger.error("[Crypto::SmcScanJob] args=#{job.arguments.inspect}")
    end

    # @param symbols [Array<String>, String, nil] nil scans everything configured
    def perform(symbols = nil)
      unless Config.enabled?
        Rails.logger.debug('[Crypto::SmcScanJob] skipped — CRYPTO_SMC_ENABLED is not true')
        return
      end

      # Before scanning, not after: a scan that finds nothing because Binance
      # is unreachable is indistinguishable from a quiet market, and this is
      # the only thing in the scheduled path that can tell them apart. The
      # probe announces on state change only, so it is silent on a normal run.
      health = Healthcheck.report
      return [] unless health.ok?

      results = Scanner.call(symbols: Array(symbols).presence)
      log(results)
      results
    end

    private

    def log(results)
      if results.empty?
        Rails.logger.info('[Crypto::SmcScanJob] no qualifying setups')
        return
      end

      results.each do |result|
        Rails.logger.info(
          "[Crypto::SmcScanJob] #{result.symbol} #{result.setup.side} " \
          "score=#{result.setup.score} rr=#{result.setup.risk_reward} status=#{result.status}"
        )
      end
    end
  end
end
