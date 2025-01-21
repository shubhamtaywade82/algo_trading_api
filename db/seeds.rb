# frozen_string_literal: true

# Strategies Data
STRATEGIES_DATA = [
  {
    name: 'Long Call',
    objective: 'Profit from a rise in the underlying price.',
    how_it_works: 'Buy a call option with a strike price near the current price.',
    risk: 'Limited to the premium paid.',
    reward: 'Unlimited (depending on the price rise).',
    best_used_when: 'Strong bullish outlook or high probability of a quick price rise.',
    example: 'Buy Nifty 24,000 CE at ₹100.'
  },
  {
    name: 'Long Put',
    objective: 'Profit from a fall in the underlying price.',
    how_it_works: 'Buy a put option with a strike price near the current price.',
    risk: 'Limited to the premium paid.',
    reward: 'Substantial if the price drops sharply.',
    best_used_when: 'Strong bearish outlook or anticipation of a quick downward move.',
    example: 'Buy Nifty 24,000 PE at ₹120.'
  },
  {
    name: 'Long Straddle',
    objective: 'Profit from significant price movement in either direction.',
    how_it_works: 'Buy a call and put at the same strike price and expiration.',
    risk: 'Double premium paid (call + put).',
    reward: 'Unlimited if the price moves significantly in either direction.',
    best_used_when: 'Expecting high volatility (e.g., before events like earnings or FOMC meetings).',
    example: 'Buy Nifty 24,000 CE and 24,000 PE.'
  },
  {
    name: 'Long Strangle',
    objective: 'Profit from significant price movement in either direction but cheaper than straddle.',
    how_it_works: 'Buy a call and a put at different OTM strikes.',
    risk: 'Lower premium than straddle but needs a bigger move to profit.',
    reward: 'Unlimited if price moves sharply in either direction.',
    best_used_when: 'Expecting volatility but want lower cost than straddle.',
    example: 'Buy Nifty 24,100 CE and 23,900 PE.'
  },
  {
    name: 'Long Butterfly Spread',
    objective: 'Benefit from a moderate move with limited risk.',
    how_it_works: 'Buy 1 ITM call/put, 1 ATM call/put, and 1 OTM call/put.',
    risk: 'Limited to the net premium paid.',
    reward: 'Limited but occurs if the price stays near the middle strike.',
    best_used_when: 'You expect a moderate move, not extreme volatility.',
    example: 'Buy 23,900 PE, Buy 24,000 PE, and Buy 24,100 PE.'
  },
  {
    name: 'Long Calendar Spread',
    objective: 'Profit from time decay differences or anticipated price movement.',
    how_it_works: 'Buy a long-dated option and sell a near-dated option at the same strike.',
    risk: 'Limited to the net premium of the long-dated option.',
    reward: 'Moderate if the price moves in the anticipated direction slowly.',
    best_used_when: 'Expecting moderate movement over time.',
    example: 'Buy Nifty 24,000 CE (Jan Expiry) and Sell Nifty 24,000 CE (Dec Expiry).'
  },
  {
    name: 'Long Iron Condor',
    objective: 'Capture profits from moderate volatility.',
    how_it_works: 'Buy 1 OTM call and 1 OTM put far from the current price.',
    risk: 'Limited to the net premium.',
    reward: 'Occurs if the price moves sharply beyond either strike.',
    best_used_when: 'Expecting moderate volatility.',
    example: 'Buy 24,200 CE and 23,800 PE.'
  },
  {
    name: 'Long Vega (Volatility Play)',
    objective: 'Profit from a spike in implied volatility (IV).',
    how_it_works: 'Buy options with high sensitivity to IV (long-dated, slightly OTM options).',
    risk: 'Limited to the premium, but profits depend on IV increasing.',
    reward: 'Gains if IV increases before significant movement.',
    best_used_when: 'Anticipating a sudden rise in IV.',
    example: 'Buy Nifty 24,500 CE at ₹90.'
  },
  {
    name: 'Protective Long Put',
    objective: 'Protect a portfolio from downside risk.',
    how_it_works: 'Buy a put option to hedge against a fall in the underlying.',
    risk: 'Limited to the premium paid.',
    reward: 'Gains if the underlying drops significantly.',
    best_used_when: 'You hold equity positions and expect potential downside.',
    example: 'Buy Nifty 24,000 PE at ₹50 to hedge your equity portfolio.'
  },
  {
    name: 'Long Ratio Backspread',
    objective: 'Profit from strong price movement with low initial cost.',
    how_it_works: 'Buy 2 OTM options and sell 1 ITM option.',
    risk: 'Limited premium but highly directional.',
    reward: 'High if the price moves significantly in the expected direction.',
    best_used_when: 'Expecting strong movement in one direction.',
    example: 'Buy 2 Nifty 24,200 CE and Sell 1 Nifty 24,000 CE.'
  },
  {
    name: 'Iron Butterfly',
    objective: 'Profit from low volatility and a stable market.',
    how_it_works: 'Sell a straddle and buy strangles at further OTM strikes to limit risk.',
    risk: 'Limited to the net premium paid.',
    reward: 'Limited to the net premium received if the price stays near the strike price.',
    best_used_when: 'Market is expected to remain stable with low volatility.',
    example: 'Sell Nifty 24,000 CE, Sell Nifty 24,000 PE, Buy Nifty 24,100 CE, and Buy Nifty 23,900 PE.'
  },
  {
    name: 'Short Straddle',
    objective: 'Profit from minimal price movement.',
    how_it_works: 'Sell both a call and a put at the same strike price and expiration.',
    risk: 'Unlimited if the price moves significantly in either direction.',
    reward: 'Limited to the premium received.',
    best_used_when: 'Expecting low volatility.',
    example: 'Sell Nifty 24,000 CE and 24,000 PE.'
  },
  {
    name: 'Short Strangle',
    objective: 'Profit from minimal price movement with lower risk than a straddle.',
    how_it_works: 'Sell both a call and a put at different OTM strikes.',
    risk: 'Limited, but requires the price to stay within a range.',
    reward: 'Limited to the premium received.',
    best_used_when: 'Expecting low volatility with reduced risk.',
    example: 'Sell Nifty 24,100 CE and 23,900 PE.'
  },
  {
    name: 'Bull Call Spread',
    objective: 'Profit from a moderate rise in the underlying price.',
    how_it_works: 'Buy a lower strike call and sell a higher strike call.',
    risk: 'Limited to the net premium paid.',
    reward: 'Limited to the difference between strike prices minus the premium paid.',
    best_used_when: 'Expecting a moderate bullish movement.',
    example: 'Buy Nifty 24,000 CE at ₹100 and Sell Nifty 24,100 CE at ₹60.'
  },
  {
    name: 'Bear Put Spread',
    objective: 'Profit from a moderate fall in the underlying price.',
    how_it_works: 'Buy a higher strike put and sell a lower strike put.',
    risk: 'Limited to the net premium paid.',
    reward: 'Limited to the difference between strike prices minus the premium paid.',
    best_used_when: 'Expecting a moderate bearish movement.',
    example: 'Buy Nifty 24,000 PE at ₹120 and Sell Nifty 23,900 PE at ₹80.'
  }
].freeze

# Create strategies in the database
STRATEGIES_DATA.each do |strategy_data|
  next if Strategy.exists?(name: strategy_data[:name])

  Strategy.create!(strategy_data)
end

Rails.logger.debug { "Seeded #{STRATEGIES_DATA.size} strategies successfully." }
