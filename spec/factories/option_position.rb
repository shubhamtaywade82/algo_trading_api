# frozen_string_literal: true

FactoryBot.define do
  #
  # Build a **raw Hash** identical to a single element of
  # `Dhanhq::API::Portfolio.positions`.
  #
  # ――― Usage quick-ref ――――――――――――――――――――――――――――――――――――――――――――
  #   build(:option_position, :long_pe)                     # default strike/qty
  #   build(:option_position, :long_ce, strike: 47000)
  #   build(:option_position, :short_pe, qty: 500)
  #
  factory :option_position, class: Hash do
    #
    # ───────────────  Transients  ──────────────────────────
    #
    # Four flavours: :long_ce  (default) / :long_pe / :short_ce / :short_pe
    transient do
      flavour     { :long_ce }
      strike      { 24_650 }       # numeric
      qty         { 1_425 }        # *absolute* lot qty (positive)
      price       { 50.10 }        # buyAvg
      expiry      { Date.parse('17-07-2025') } # Date or string
      product     { 'MARGIN' } # or 'INTRADAY'
      client_id   { '1104216308' }
    end

    # ───────────── Core position fields (exact API keys) ─────────────
    dhanClientId { client_id }
    tradingSymbol do
      month_tag = expiry.strftime('%b').capitalize        # "Jun"
      year_tag  = expiry.strftime('%Y')                   # "2025"
      opt       = flavour.to_s.include?('pe') ? 'PE' : 'CE'
      "NIFTY-#{month_tag}#{year_tag}-#{strike}-#{opt}"
    end
    securityId          { rand(40_000..60_000).to_s }
    positionType        { netQty.positive? ? 'LONG' : 'SHORT' }
    exchangeSegment     { 'NSE_FNO' }
    productType         { product }

    buyAvg              { price }
    costPrice           { price * (1 + (rand * 0.8)) } # any float – rarely used in specs

    # qty
    netQty do
      sign = flavour.to_s.start_with?('short') ? -1 : 1
      sign * qty
    end
    buyQty              { netQty.positive? ? netQty : 0 }
    sellQty             { netQty.negative? ? netQty.abs : 0 }

    sellAvg             { 0.0 }

    realizedProfit      { 0.0 }
    unrealizedProfit    { 0.0 }

    rbiReferenceRate    { 1.0 }
    multiplier          { 1_000 }

    carryForwardBuyQty  { buyQty }
    carryForwardSellQty { 0 }
    carryForwardBuyValue { buyQty * buyAvg }
    carryForwardSellValue { 0.0 }

    dayBuyQty           { 0 }
    daySellQty          { 0 }
    dayBuyValue         { 0.0 }
    daySellValue        { 0.0 }

    drvExpiryDate       { expiry.to_s }
    drvOptionType       { flavour.to_s.include?('pe') ? 'PUT' : 'CALL' }
    drvStrikePrice      { strike.to_f }

    crossCurrency       { false }

    # -----------------------------------------------------------------
    initialize_with { attributes } # ensure a plain Hash is returned
  end
end