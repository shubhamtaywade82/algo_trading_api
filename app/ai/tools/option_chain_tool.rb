# frozen_string_literal: true

module AI
  module Tools
    # Fetches and analyzes the option chain for an index via existing ChainAnalyzer.
    class OptionChainTool < ::Agents::Tool
      description 'Fetch and analyze the option chain for an NSE index (NIFTY, BANKNIFTY, FINNIFTY). Returns IV rank, ATM strike data, PCR, and recommended strikes.'

      param :symbol,      type: 'string', desc: 'Index symbol: NIFTY, BANKNIFTY, or FINNIFTY'
      param :expiry,      type: 'string', desc: 'Expiry date YYYY-MM-DD (optional, defaults to nearest)', required: false
      param :signal_type, type: 'string', desc: 'Signal direction for strike recommendation: ce (bullish), pe (bearish)', required: false

      def perform(_ctx, symbol:, expiry: nil, signal_type: 'ce')
        sym  = symbol.to_s.upcase
        stype = signal_type.to_s.presence || 'ce'

        instrument = Instrument.segment_index.find_by(underlying_symbol: sym)
        return { error: "Index instrument not found: #{sym}" } unless instrument

        expiry ||= instrument.expiry_list&.first
        return { error: "No expiry available for #{sym}" } unless expiry

        chain = instrument.fetch_option_chain(expiry)
        return { error: 'Option chain unavailable' } unless chain

        ltp      = instrument.ltp.to_f
        iv_rank  = Option::ChainAnalyzer.estimate_iv_rank(chain)

        historical = Option::HistoricalDataFetcher.for_strategy(instrument, strategy_type: 'intraday')
        analyzer   = Option::ChainAnalyzer.new(
          chain,
          expiry:          expiry,
          underlying_spot: ltp,
          iv_rank:         iv_rank,
          historical_data: historical
        )

        analysis  = analyzer.analyze(strategy_type: 'intraday', signal_type: stype.to_sym)
        sentiment = Market::SentimentAnalysis.call(
          option_chain:    chain,
          expiry:         expiry,
          spot:           ltp,
          iv_rank:        iv_rank,
          historical_data: historical
        )

        {
          symbol:        sym,
          expiry:        expiry,
          ltp:           ltp.round(2),
          iv_rank:       iv_rank&.round(2),
          pcr:           compute_pcr(chain),
          sentiment:     sentiment[:bias]&.to_s,
          best_strike:   analysis[:best_strike],
          top_strikes:   analysis[:strikes]&.first(3),
          trend:         analysis[:trend],
          chain_summary: summarize_chain(chain, ltp)
        }
      rescue StandardError => e
        { error: e.message }
      end

      private

      def compute_pcr(chain)
        return nil unless chain.is_a?(Hash) && chain[:oc].is_a?(Hash)

        total_ce_oi = 0
        total_pe_oi = 0
        chain[:oc].each_value do |row|
          data = (row || {}).with_indifferent_access
          total_ce_oi += data.dig('ce', 'oi').to_i
          total_pe_oi += data.dig('pe', 'oi').to_i
        end
        return nil if total_ce_oi.zero?

        (total_pe_oi.to_f / total_ce_oi).round(3)
      end

      def summarize_chain(chain, ltp)
        oc = chain.is_a?(Hash) ? chain[:oc] || chain['oc'] : {}
        return [] unless oc.is_a?(Hash) && oc.any?

        atm_strike = (ltp / 50.0).round * 50
        strikes = oc.map do |strike_str, row|
          strike = strike_str.to_f
          [strike, row]
        end.select { |strike, _| (strike - atm_strike).abs <= 200 }.sort_by { |strike, _| (strike - ltp).abs }.first(5)

        strikes.map do |strike, row|
          row = (row || {}).with_indifferent_access
          {
            strike: strike,
            ce_ltp: row.dig('ce', 'last_price').to_f.round(2),
            pe_ltp: row.dig('pe', 'last_price').to_f.round(2),
            ce_oi:  row.dig('ce', 'oi').to_i,
            pe_oi:  row.dig('pe', 'oi').to_i,
            ce_iv:  row.dig('ce', 'implied_volatility').to_f.round(2),
            pe_iv:  row.dig('pe', 'implied_volatility').to_f.round(2)
          }
        end
      end
    end
  end
end
