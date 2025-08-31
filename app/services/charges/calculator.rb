# frozen_string_literal: true

module Charges
  class Calculator < ApplicationService
    # Brokerage and Charges Constants (Dhan)
    BROKERAGE_OPTION = 20.0 # Flat ₹20 per executed order (Options)
    BROKERAGE_FUTURE_MAX = 20.0
    BROKERAGE_FUTURE_PCT = 0.0003 # 0.03%
    BROKERAGE_INTRADAY_MAX = 20.0
    BROKERAGE_INTRADAY_PCT = 0.0003
    BROKERAGE_DELIVERY = 0.0

    # Transaction Charges (NSE rates)
    TRANSACTION_CHARGE_OPT = 0.0003503    # 0.03503% (Options, on premium)
    TRANSACTION_CHARGE_FUT = 0.0000173    # 0.00173% (Futures, on turnover)
    TRANSACTION_CHARGE_EQ  = 0.0000297    # 0.00297% (Intraday Equity, on turnover)

    GST_RATE = 0.18
    STT_OPTION = 0.001       # 0.1% on sell side (Options, on premium)
    STT_FUTURE = 0.0002      # 0.02% on sell side (Futures)
    STT_INTRADAY = 0.00025   # 0.025% on sell side (Intraday Equity)
    STT_DELIVERY = 0.001     # 0.1% on buy & sell (Delivery Equity)

    SEBI_FEES = 0.000001     # 0.0001% of turnover
    STAMP_DUTY_OPT = 0.00003 # 0.003% on buy side (Options)
    STAMP_DUTY_EQ_INTRADAY = 0.00003  # 0.003% on buy side (Intraday Equity)
    STAMP_DUTY_EQ_DELIVERY = 0.00015  # 0.015% on buy side (Delivery Equity)
    STAMP_DUTY_FUTURE = 0.00002       # 0.002% on buy side (Futures)
    IPFT_OPT = 0.000005      # 0.0005% for options
    IPFT_OTHER = 0.000001    # 0.0001% for others

    def initialize(position, analysis)
      @position = position.with_indifferent_access
      @a = analysis
      @type = instrument_type(@position)
    end

    def call
      entry = PriceMath.round_tick(@a[:entry_price].to_f)
      ltp   = PriceMath.round_tick(@a[:ltp].to_f)
      qty   = @a[:quantity].to_i

      # Turnover logic
      turnover = case @type
                 when :option
                   ltp * qty # premium-based turnover for option sell
                 when :future
                   (entry + ltp) * qty
                 when :equity_intraday, :equity_delivery
                   (entry + ltp) * qty
                 else
                   (entry + ltp) * qty
                 end

      # Brokerage
      brokerage =
        case @type
        when :option
          BROKERAGE_OPTION
        when :future
          [BROKERAGE_FUTURE_MAX, BROKERAGE_FUTURE_PCT * turnover].min
        when :equity_intraday
          [BROKERAGE_INTRADAY_MAX, BROKERAGE_INTRADAY_PCT * turnover].min
        when :equity_delivery
          BROKERAGE_DELIVERY
        else
          BROKERAGE_OPTION
        end

      # Transaction charges
      transaction_charges =
        case @type
        when :option
          ltp * qty * TRANSACTION_CHARGE_OPT
        when :future
          turnover * TRANSACTION_CHARGE_FUT
        when :equity_intraday
          turnover * TRANSACTION_CHARGE_EQ
        else
          0
        end

      # STT logic
      stt =
        case @type
        when :option
          ltp * qty * STT_OPTION # Only on sell side, so this is accurate for exit
        when :future
          ltp * qty * STT_FUTURE
        when :equity_intraday
          ltp * qty * STT_INTRADAY
        when :equity_delivery
          ((entry * qty) + (ltp * qty)) * STT_DELIVERY
        else
          0
        end

      sebi_fees = turnover * SEBI_FEES

      # Stamp duty (usually on buy side only, use entry)
      stamp_duty =
        case @type
        when :option
          entry * qty * STAMP_DUTY_OPT
        when :future
          entry * qty * STAMP_DUTY_FUTURE
        when :equity_intraday
          entry * qty * STAMP_DUTY_EQ_INTRADAY
        when :equity_delivery
          entry * qty * STAMP_DUTY_EQ_DELIVERY
        else
          0
        end

      ipft =
        case @type
        when :option
          turnover * IPFT_OPT
        else
          turnover * IPFT_OTHER
        end

      gst = (brokerage + transaction_charges + sebi_fees + ipft) * GST_RATE

      total = brokerage + transaction_charges + sebi_fees + stt + stamp_duty + ipft + gst

      PriceMath.round_tick(total)
    end

    private

    # Map Dhan's segment/productType/symbol to our logic
    def instrument_type(pos)
      segment = pos['exchangeSegment']
      prod    = pos['productType']
      sym     = pos['tradingSymbol'].to_s.upcase

      case segment
      when 'NSE_FNO', 'BSE_FNO'
        if sym.match?(/CE$|PE$|OPT/)
          :option
        elsif sym.include?('FUT')
          :future
        else
          :future # Default FNO
        end
      when 'NSE_EQ', 'BSE_EQ'
        prod == 'CNC' ? :equity_delivery : :equity_intraday
      else
        :option # Default fallback, safe for option-heavy usage
      end
    end
  end
end
