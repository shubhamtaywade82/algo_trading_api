# frozen_string_literal: true

module Paper
  # Per-fill charges on the Dhan schedule.
  #
  # This is not a duplicate of {Charges::Calculator}: that one prices a
  # *round trip* from an open position and its exit, which is what the exit
  # notifier needs. A simulated fill has to be charged when it happens, on one
  # side only, before any exit exists — different inputs, different answer.
  #
  # Rates are the published Dhan/NSE schedule. STT asymmetry matters: it falls
  # on the sell side for intraday and F&O but both sides for delivery, which is
  # why a paper strategy that ignores it over-reports intraday profit.
  class CostCalculator
    RATES = {
      equity_delivery: {
        brokerage: 0.0, brokerage_pct: nil,
        stt_buy: 0.001, stt_sell: 0.001,
        exchange: 0.0000297, stamp_duty_buy: 0.00015, sebi: 0.000001
      },
      equity_intraday: {
        brokerage: 20.0, brokerage_pct: 0.0003,
        stt_buy: 0.0, stt_sell: 0.00025,
        exchange: 0.0000297, stamp_duty_buy: 0.00003, sebi: 0.000001
      },
      fno: {
        brokerage: 20.0, brokerage_pct: nil,
        stt_buy: 0.0, stt_sell: 0.000625,
        exchange: 0.0000357, stamp_duty_buy: 0.00003, sebi: 0.000001
      }
    }.freeze

    GST_RATE = 0.18

    # @return [Hash] each component plus :total, all rounded to paise
    def calculate(transaction_type:, exchange_segment:, product_type:, quantity:, price:)
      turnover = quantity.to_i * price.to_f
      return zero_result if turnover <= 0

      rates = RATES.fetch(charge_type(exchange_segment, product_type))
      buy = transaction_type.to_s.casecmp('BUY').zero?

      brokerage = brokerage_for(rates, turnover)
      stt = turnover * (buy ? rates[:stt_buy] : rates[:stt_sell])
      exchange = turnover * rates[:exchange]
      stamp = buy ? turnover * rates[:stamp_duty_buy] : 0.0
      sebi = turnover * rates[:sebi]
      # GST applies to brokerage and exchange charges, not the statutory levies.
      gst = (brokerage + exchange) * GST_RATE

      {
        brokerage: brokerage.round(2),
        stt: stt.round(2),
        exchange_charges: exchange.round(2),
        stamp_duty: stamp.round(2),
        sebi_tax: sebi.round(4),
        gst: gst.round(2),
        total: (brokerage + stt + exchange + stamp + sebi + gst).round(2)
      }
    end

    private

    def charge_type(exchange_segment, product_type)
      return :fno if exchange_segment.to_s.include?('FNO')
      return :equity_delivery if product_type.to_s.casecmp('CNC').zero?

      :equity_intraday
    end

    # Dhan charges the lower of a flat fee and a percentage, where both apply.
    def brokerage_for(rates, turnover)
      flat = rates[:brokerage].to_f
      return 0.0 if flat.zero?
      return flat unless rates[:brokerage_pct]

      [flat, turnover * rates[:brokerage_pct]].min
    end

    def zero_result
      { brokerage: 0.0, stt: 0.0, exchange_charges: 0.0, stamp_duty: 0.0, sebi_tax: 0.0, gst: 0.0, total: 0.0 }
    end
  end
end
