# frozen_string_literal: true

module AI
  module Tools
    # Returns aggregated market sentiment indicators for NSE indices.
    class MarketSentimentTool < ::Agents::Tool
      description 'Get market sentiment indicators: India VIX, PCR, and derived bias for NIFTY and BANKNIFTY.'

      param :symbol, type: 'string', desc: 'Index symbol: NIFTY or BANKNIFTY'

      def perform(_ctx, symbol:)
        sym = symbol.to_s.upcase

        instrument = Instrument.segment_index.find_by(underlying_symbol: sym)
        return { error: "Instrument not found: #{sym}" } unless instrument

        vix = india_vix_ltp

        chain = begin
          instrument.fetch_option_chain(instrument.expiry_list&.first)
        rescue StandardError
          nil
        end

        sentiment = if chain
                      iv_rank = Option::ChainAnalyzer.estimate_iv_rank(chain)
                      spot = instrument.ltp.to_f || chain[:last_price].to_f
                      expiry = instrument.expiry_list&.first
                      historical = Option::HistoricalDataFetcher.for_strategy(instrument, strategy_type: 'intraday')
                      Market::SentimentAnalysis.call(
                        option_chain:    chain,
                        expiry:         expiry,
                        spot:           spot,
                        iv_rank:        iv_rank,
                        historical_data: historical
                      )
                    else
                      {}
                    end

        pcr = compute_pcr(chain)
        {
          symbol:    sym,
          ltp:       instrument.ltp.to_f.round(2),
          vix:       vix,
          vix_level: categorize_vix(vix),
          pcr:       pcr&.round(3),
          sentiment: sentiment[:bias]&.to_s,
          bias:      derive_bias(pcr, sentiment[:bias], vix),
          timestamp: Time.current.strftime('%Y-%m-%dT%H:%M:%S%z')
        }
      rescue StandardError => e
        { error: e.message }
      end

      private

      def india_vix_ltp
        Instrument.find_by(security_id: 21)&.ltp.to_f.round(2)
      rescue StandardError
        nil
      end

      def categorize_vix(vix)
        return 'unknown'  if vix.nil? || vix.zero?
        return 'low'      if vix <= 11
        return 'elevated' if vix <= 16
        return 'high'     if vix <= 20

        'extreme'
      end

      def derive_bias(pcr, bias_from_sentiment, vix)
        return bias_from_sentiment&.to_s.presence || 'neutral' if pcr.nil?

        pcr = pcr.to_f
        bullish = (pcr > 1.2 ? 1 : 0) + (vix.to_f < 13 ? 1 : 0)
        bearish = (pcr < 0.8 ? 1 : 0) + (vix.to_f > 18 ? 1 : 0)

        return 'bullish' if bullish > bearish
        return 'bearish' if bearish > bullish

        bias_from_sentiment&.to_s.presence || 'neutral'
      end

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

        total_pe_oi.to_f / total_ce_oi
      end
    end
  end
end
