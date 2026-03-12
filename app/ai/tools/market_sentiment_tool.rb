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

        sentiment = chain ? Market::SentimentAnalysis.call(chain) : {}

        {
          symbol:    sym,
          ltp:       instrument.ltp.to_f.round(2),
          vix:       vix,
          vix_level: categorize_vix(vix),
          pcr:       sentiment[:pcr]&.round(3),
          sentiment: sentiment[:sentiment],
          bias:      derive_bias(sentiment, vix),
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

      def derive_bias(sentiment, vix)
        pcr = sentiment[:pcr].to_f
        bullish = (pcr > 1.2 ? 1 : 0) + (vix.to_f < 13 ? 1 : 0)
        bearish = (pcr < 0.8 ? 1 : 0) + (vix.to_f > 18 ? 1 : 0)

        return 'bullish' if bullish > bearish
        return 'bearish' if bearish > bullish

        'neutral'
      end
    end
  end
end
