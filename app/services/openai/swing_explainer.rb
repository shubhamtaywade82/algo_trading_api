# frozen_string_literal: true

module Openai
  class SwingExplainer
    CACHE_TTL = 12.hours

    # Call this from SwingScreenerService
    def self.explain_with_cache(pick)
      key = cache_key(pick)
      Rails.cache.fetch(key, expires_in: CACHE_TTL) do
        explain(pick[:instrument].symbol_name,
                price: pick[:close_price],
                rsi: pick[:rsi],
                ema: pick[:ema],
                high20: pick[:high20],
                low20: pick[:low20],
                setup_type: pick[:setup_type])
      end
    end

    def self.explain(symbol, price:, rsi:, ema:, high20:, low20:, setup_type:)
      explanation = <<~PROMPT
        Symbol: #{symbol}
        Price: ₹#{PriceMath.round_tick(price)}
        EMA(200): #{PriceMath.round_tick(ema)}
        ATR: #{PriceMath.round_tick(atr)}
        20-Day High: #{PriceMath.round_tick(high20)}
        20-Day Low: #{PriceMath.round_tick(low20)}
        Setup Type: #{setup_type.capitalize}

        Provide a short explanation in simple words on why this #{setup_type} setup is significant for swing trading. Mention how the current price, EMA, RSI and Donchian levels support the trade idea.
        Keep it ≤ 80 words. Focus on technical confirmation only. Respond without bullet points.
      PROMPT

      ChatRouter.ask!(explanation, temperature: 0.4)
    end

    def self.cache_key(pick)
      "swing:explanation:#{pick[:instrument].symbol_name}:#{pick[:setup_type]}:#{Time.zone.today}"
    end
  end
end
