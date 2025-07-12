FactoryBot.define do
  factory :option_position, class: Hash do
    initialize_with { attributes }

    securityId        { 123 }
    exchangeSegment   { 'NSE_FNO' }
    productType       { 'INTRADAY' }
    tradingSymbol     { 'NIFTY24JUL25000CE' }
    netQty            { 75 } # long CE
    costPrice         { 100.0 }
    buyAvg            { 100.0 }
    drvExpiryDate     { 1.week.from_now.to_date }
  end
end
