# frozen_string_literal: true

module Paper
  # Entry point for simulated placement, kept as the name {Orders::Gateway}
  # routes to. The simulation itself lives in {Paper::Exchange}.
  #
  # This is a step beyond the SDK's `DHAN_DRY_RUN`, which suppresses the request
  # and returns a `DRYRUN-…` id without modelling the outcome. Here an order is
  # matched against live prices, charged, and reflected in virtual capital and
  # positions.
  class Broker
    class << self
      # @param payload [Hash] the same payload a live placement takes
      # @param source [String, nil] caller identifier for logs
      # @return [Hash] gateway-shaped result
      def place(payload, source: nil)
        Paper::Exchange.place(payload, source: source)
      end

      # @return [Boolean] whether paper trading is switched on
      def enabled?
        ENV['PAPER_TRADING'] == 'true'
      end

      # Slippage is configured per account now; this remains for callers that
      # only want to report the current assumption.
      # @return [Float]
      def slippage_pct
        (PaperAccount.current.settings['slippage_bps'].to_f / 100.0).round(4)
      rescue StandardError
        0.05
      end
    end
  end
end
