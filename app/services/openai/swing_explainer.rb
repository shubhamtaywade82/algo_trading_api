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
        Price: ₹#{price.round(2)}
        EMA(200): #{ema.round(2)}
        RSI(14): #{rsi.round(1)}
        20-Day High: #{high20.round(2)}
        20-Day Low: #{low20.round(2)}
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
