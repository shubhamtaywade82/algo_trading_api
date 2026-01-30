# frozen_string_literal: true

require 'ostruct'

# Demo AI analysis prompt for testing the LLM (OpenAI or Ollama) without live market data.
# Usage:
#   DemoAiAnalysis.prompt                    # => full user prompt string (analysis style)
#   DemoAiAnalysis.prompt(trade_type: :options_buying)  # options-buying style
#   DemoAiAnalysis.run                       # build prompt, call LLM, return response
#   DemoAiAnalysis.run(trade_type: :options_buying)
module DemoAiAnalysis
  # Minimal option-chain snapshot for demo (ATM + one OTM each side).
  def self.demo_options_snapshot
    {
      atm: {
        strike: 24_350,
        call: { 'last_price' => 125.50, 'oi' => 450_000, 'implied_volatility' => 14.2, 'greeks' => { 'delta' => 0.52 } },
        put: { 'last_price' => 118.00, 'oi' => 420_000, 'implied_volatility' => 14.0, 'greeks' => { 'delta' => -0.48 } }
      },
      otm_call: {
        strike: 24_400,
        call: { 'last_price' => 85.00, 'oi' => 320_000, 'implied_volatility' => 13.8, 'greeks' => { 'delta' => 0.38 } },
        put: { 'last_price' => 45.00, 'oi' => 280_000, 'implied_volatility' => 13.5, 'greeks' => { 'delta' => -0.22 } }
      },
      otm_put: {
        strike: 24_300,
        call: { 'last_price' => 165.00, 'oi' => 380_000, 'implied_volatility' => 14.5, 'greeks' => { 'delta' => 0.62 } },
        put: { 'last_price' => 95.00, 'oi' => 410_000, 'implied_volatility' => 14.2, 'greeks' => { 'delta' => -0.38 } }
      }
    }
  end

  # Minimal SMC-like structure for options_buying prompt (avoids nil dig).
  def self.demo_smc_snapshot
    {
      m15: OpenStruct.new(
        market_structure: 'bullish',
        last_swing_high: { price: 24_400 },
        last_swing_low: { price: 24_280 },
        last_bos: { direction: 'bullish', level: 24_320 }
      ),
      m5: OpenStruct.new(
        market_structure: 'bullish',
        last_bos: { direction: 'bullish', level: 24_335 }
      )
    }
  end

  def self.demo_value_snapshot
    {
      m15: { vwap: 24_328.5, avwap_bos: 24_315, avrz: { low: 24_280, mid: 24_320, high: 24_360, regime: 'neutral' } },
      m5: { vwap: 24_332, avwap_bos: 24_318, avrz: { low: 24_290, mid: 24_330, high: 24_370, regime: 'neutral' } }
    }
  end

  # Sample market data sufficient for Market::PromptBuilder (analysis or options_buying).
  # Replace with real data when running live.
  DEMO_MARKET_DATA = {
    symbol: 'NIFTY',
    session: :live,
    vix: 13.2,
    ltp: 24_350.50,
    frame: '15m',
    expiry: '2025-01-30',
    prev_day: { open: 24_280, high: 24_420, low: 24_200, close: 24_380 },
    ohlc: { open: 24_320, high: 24_365, low: 24_310, close: 24_350, volume: 1_250_000 },
    atr: 85.0,
    rsi: 52,
    super: 'bullish',
    hi20: 24_400,
    lo20: 24_250,
    liq_up: false,
    liq_dn: false,
    boll: { upper: 24_420, middle: 24_320, lower: 24_220 },
    macd: { macd: 12.5, signal: 8.2, hist: 4.3 },
    options: demo_options_snapshot,
    smc: demo_smc_snapshot,
    value: demo_value_snapshot
  }.freeze

  class << self
    # Returns the built user prompt string (no LLM call).
    # @param trade_type [Symbol] :analysis or :options_buying
    def prompt(trade_type: :analysis)
      Market::PromptBuilder.build_prompt(DEMO_MARKET_DATA.dup, trade_type: trade_type)
    end

    # Builds the demo prompt, calls the LLM, and returns the response text.
    # @param trade_type [Symbol] :analysis or :options_buying
    def run(trade_type: :analysis)
      user_prompt = prompt(trade_type: trade_type)
      system_prompt = Market::PromptBuilder.system_prompt(trade_type)
      Openai::ChatRouter.ask!(user_prompt, system: system_prompt)
    end
  end
end
