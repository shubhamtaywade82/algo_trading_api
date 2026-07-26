# frozen_string_literal: true

module Paper
  # Simplified margin model for the simulated book.
  #
  # Real F&O margin is SPAN + exposure, computed by the exchange against the
  # whole portfolio with hedge benefits. Reproducing that faithfully is a
  # project in itself, so this uses flat per-segment rates: enough to make a
  # paper account run out of capital roughly when a real one would, which is
  # the point — an unconstrained paper book will happily "trade" positions you
  # could never have funded.
  #
  # It is deliberately conservative for options *buying* (premium is the true
  # cost) and understates naked option *selling*, where real SPAN is far
  # higher. Do not use paper margin to size a short-vol strategy.
  class MarginCalculator
    RATES = {
      'NSE_EQ' => { 'CNC' => 1.0, 'INTRADAY' => 0.2, 'MTF' => 0.25, 'MARGIN' => 0.25 },
      'BSE_EQ' => { 'CNC' => 1.0, 'INTRADAY' => 0.2, 'MARGIN' => 0.25 },
      'NSE_FNO' => { 'INTRADAY' => 0.3, 'MARGIN' => 0.4, 'CNC' => 0.4 },
      'BSE_FNO' => { 'INTRADAY' => 0.3, 'MARGIN' => 0.4 },
      'MCX_COMM' => { 'INTRADAY' => 0.15, 'MARGIN' => 0.25 },
      'NSE_CURRENCY' => { 'INTRADAY' => 0.05, 'MARGIN' => 0.1 },
      'BSE_CURRENCY' => { 'INTRADAY' => 0.05, 'MARGIN' => 0.1 }
    }.freeze

    DEFAULT_RATE = 1.0

    def initialize(config = {})
      @config = (config || {}).with_indifferent_access
    end

    # @return [Hash] :sufficient, :required, :available
    def check(account, exchange_segment:, product_type:, quantity:, price:)
      required = required_for(exchange_segment: exchange_segment, product_type: product_type,
                              quantity: quantity, price: price)
      available = account.free_margin.to_f

      { sufficient: available >= required, required: required, available: available }
    end

    # Commits margin against the account.
    def block!(account, amount)
      return if amount.to_f <= 0

      account.update!(
        blocked_margin: account.blocked_margin.to_f + amount.to_f,
        utilized_margin: account.utilized_margin.to_f + amount.to_f
      )
    end

    # Returns margin to the account, never below zero.
    def release!(account, amount)
      return if amount.to_f <= 0

      account.update!(
        blocked_margin: [account.blocked_margin.to_f - amount.to_f, 0].max,
        utilized_margin: [account.utilized_margin.to_f - amount.to_f, 0].max
      )
    end

    # @return [Float] margin a position of this size would consume
    def required_for(exchange_segment:, product_type:, quantity:, price:)
      turnover = quantity.to_i * price.to_f
      return 0.0 if turnover <= 0

      rate = RATES.dig(exchange_segment.to_s, product_type.to_s.upcase) || DEFAULT_RATE
      (turnover * rate).round(2)
    end
  end
end
