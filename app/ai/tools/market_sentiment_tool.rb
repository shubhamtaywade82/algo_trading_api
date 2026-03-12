# frozen_string_literal: true

module AI
  module Tools
    # Returns aggregated market sentiment indicators for NSE indices.
    class MarketSentimentTool < BaseTool
      TOOL_NAME   = 'get_market_sentiment'
      DESCRIPTION = 'Get market sentiment indicators: India VIX, PCR, breadth, and AI-based bias for NIFTY and BANKNIFTY.'
      PARAMETERS  = {
        type: 'object',
        properties: {
          symbol: {
            type: 'string',
            description: 'Index symbol: NIFTY or BANKNIFTY',
            enum: %w[NIFTY BANKNIFTY]
          }
        },
        required: %w[symbol]
      }.freeze

      def perform(args)
        symbol = args['symbol'].to_s.upcase

        instrument = Instrument.segment_index.find_by(underlying_symbol: symbol)
        return { error: "Instrument not found: #{symbol}" } unless instrument

        vix = india_vix_ltp

        chain = begin
          instrument.fetch_option_chain(instrument.expiry_list&.first)
        rescue StandardError
          nil
        end

        sentiment = chain ? Market::SentimentAnalysis.call(chain) : {}

        {
          symbol:    symbol,
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
        vix_instrument = Instrument.find_by(security_id: 21)
        vix_instrument&.ltp.to_f.round(2)
      rescue StandardError
        nil
      end

      def categorize_vix(vix)
        return 'unknown' if vix.nil? || vix.zero?
        return 'low'     if vix <= 11
        return 'elevated' if vix <= 16
        return 'high'    if vix <= 20

        'extreme'
      end

      def derive_bias(sentiment, vix)
        pcr = sentiment[:pcr].to_f

        bullish_signals = 0
        bearish_signals = 0

        if pcr > 1.2
          bullish_signals += 1
        elsif pcr < 0.8
          bearish_signals += 1
        end

        if vix.to_f < 13
          bullish_signals += 1
        elsif vix.to_f > 18
          bearish_signals += 1
        end

        return 'bullish' if bullish_signals > bearish_signals
        return 'bearish' if bearish_signals > bullish_signals

        'neutral'
      end
    end
  end
end
