# frozen_string_literal: true

module Crypto
  # Runs the analysis across the configured symbols and dispatches whatever
  # qualifies. This is the single entry point both triggers use — the
  # scheduled job and the WebSocket runner — so the two cannot drift apart in
  # what they consider a setup.
  #
  #   Crypto::Scanner.call                          # every configured symbol
  #   Crypto::Scanner.call(symbols: %w[SOLUSDT])    # one, after a 5m close
  #   Crypto::Scanner.call(notify: false)           # analyse, say nothing
  class Scanner
    Result = Struct.new(:symbol, :setup, :status, keyword_init: true) do
      def alerted? = status == :sent
    end

    def self.call(...) = new(...).call

    def initialize(symbols: nil, notify: true, client: nil)
      @symbols = Array(symbols.presence || Config.symbols)
      @notify  = notify
      @client  = client || Binance::Client.new
    end

    # @return [Array<Result>] one entry per symbol that produced a setup
    def call
      @symbols.filter_map { |symbol| scan(symbol) }
    end

    private

    def scan(symbol)
      setup = Analyzer.new(symbol, client: @client).call
      unless setup
        Rails.logger.debug { "[Crypto] no qualifying setup for #{symbol}" }
        return nil
      end

      status = @notify ? AlertDispatcher.dispatch(setup) : :skipped
      Result.new(symbol: symbol, setup: setup, status: status)
    rescue StandardError => e
      Rails.logger.error("[Crypto] scan failed for #{symbol}: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.first(5).join("\n"))
      nil
    end
  end
end
