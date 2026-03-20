# frozen_string_literal: true

module Mcp
  module Tools
    # Tool that wraps the deterministic trade decision engine.
    class AnalyzeTrade
      extend ExecutionHelpers
      def self.name
        'analyze_trade'
      end

      def self.definition
        {
          name: name,
          title: 'Analyze Trade',
          description: 'Runs a deterministic trade decision pipeline and returns a trade proposal (no execution).',
          inputSchema: {
            type: 'object',
            properties: {
              symbol: { type: 'string', description: 'Index symbol: NIFTY | BANKNIFTY | SENSEX' },
              expiry: { type: 'string', description: 'Expiry date YYYY-MM-DD (optional)' }
            },
            required: %w[symbol]
          }
        }
      end

      def self.execute(args)
        opts = normalize_args!(name, args).with_indifferent_access
        symbol = opts[:symbol].to_s
        expiry = opts[:expiry].presence

        result = Trading::TradeDecisionEngine.call(symbol: symbol, expiry: expiry)
        result_hash = result.to_h

        attach_execution_contract!(result_hash)
        result_hash[:timestamp] = result_hash[:timestamp]&.iso8601
        result_hash
      rescue StandardError => e
        { error: e.message }
      end

      def self.attach_execution_contract!(result_hash)
        return result_hash unless result_hash[:proceed]

        selected = result_hash[:selected_strike].to_h
        strike = selected[:strike_price] || selected[:strike]
        entry = selected[:last_price] || selected[:entry] || selected[:entry_price]

        return result_hash if strike.blank? || entry.blank?

        iv_rank_pct = result_hash[:iv_rank].to_f
        sl_pct = (0.18 + (iv_rank_pct / 100.0) * 0.03).clamp(0.15, 0.23)
        tp_pct = (0.30 + (iv_rank_pct / 100.0) * 0.05).clamp(0.25, 0.40)

        entry_price = entry.to_f
        result_hash[:strike] = strike.to_i
        result_hash[:entry] = PriceMath.round_tick(entry_price)
        result_hash[:sl] = PriceMath.round_tick(entry_price * (1.0 - sl_pct))
        result_hash[:tp] = PriceMath.round_tick(entry_price * (1.0 + tp_pct))

        result_hash
      end
    end
  end
end

