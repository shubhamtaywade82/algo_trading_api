# frozen_string_literal: true

module Mcp
  module Tools
    # Tool for computing market sentiment (VIX, PCR, derived bias).
    class GetMarketSentiment
      def self.name
        'get_market_sentiment'
      end

      def self.definition
        {
          name: name,
          title: 'Market Sentiment',
          description: 'Returns VIX, PCR and derived sentiment for an index (NIFTY/BANKNIFTY/SENSEX).',
          inputSchema: {
            type: 'object',
            properties: {
              symbol: { type: 'string', description: 'Index symbol: NIFTY | BANKNIFTY | SENSEX' }
            },
            required: %w[symbol]
          }
        }
      end

      def self.execute(args)
        opts = args.with_indifferent_access
        symbol = opts[:symbol].to_s.upcase

        instrument = resolve_instrument!(symbol)
        vix = india_vix_ltp

        chain = begin
          instrument.fetch_option_chain(instrument.expiry_list&.first)
        rescue StandardError
          nil
        end

        sentiment = chain ? compute_sentiment(instrument, chain, symbol, vix) : {}
        pcr = compute_pcr(chain)

        {
          symbol: symbol,
          ltp: instrument.ltp.to_f.round(2),
          vix: vix,
          vix_level: categorize_vix(vix),
          pcr: pcr&.round(3),
          sentiment: sentiment[:bias]&.to_s,
          bias: derive_bias(pcr, sentiment[:bias], vix),
          timestamp: Time.current.strftime('%Y-%m-%dT%H:%M:%S%z')
        }
      rescue StandardError => e
        { error: e.message }
      end

      class << self
        private

        def resolve_instrument!(symbol)
          if symbol == 'SENSEX'
            Instrument.segment_index.find_by(underlying_symbol: 'SENSEX', exchange: 'bse')
          else
            Instrument.segment_index.find_by(underlying_symbol: symbol, exchange: 'nse')
          end
        end

        def india_vix_ltp
          Instrument.find_by(security_id: 21)&.ltp.to_f.round(2)
        rescue StandardError
          nil
        end

        def categorize_vix(vix)
          return 'unknown' if vix.nil? || vix.to_f.zero?
          return 'low' if vix.to_f <= 11
          return 'elevated' if vix.to_f <= 16
          return 'high' if vix.to_f <= 20

          'extreme'
        end

        def compute_sentiment(instrument, chain, _symbol, _vix)
          iv_rank = Option::ChainAnalyzer.estimate_iv_rank(chain)
          spot = instrument.ltp.to_f || chain[:last_price].to_f
          expiry = instrument.expiry_list&.first
          historical = Option::HistoricalDataFetcher.for_strategy(instrument, strategy_type: 'intraday')

          Market::SentimentAnalysis.call(
            option_chain: chain,
            expiry: expiry,
            spot: spot,
            iv_rank: iv_rank,
            historical_data: historical
          )
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

        def derive_bias(pcr, bias_from_sentiment, vix)
          return bias_from_sentiment&.to_s.presence || 'neutral' if pcr.nil?

          bullish = (pcr.to_f > 1.2 ? 1 : 0) + (vix.to_f < 13 ? 1 : 0)
          bearish = (pcr.to_f < 0.8 ? 1 : 0) + (vix.to_f > 18 ? 1 : 0)

          return 'bullish' if bullish > bearish
          return 'bearish' if bearish > bullish

          bias_from_sentiment&.to_s.presence || 'neutral'
        end
      end
    end
  end
end

