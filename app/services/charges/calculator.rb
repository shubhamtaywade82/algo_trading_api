# frozen_string_literal: true

module Charges
  class Calculator < ApplicationService
    BROKERAGE = 20.0
    GST_RATE = 0.18
    STT_RATE = 0.00025
    TRANSACTION_CHARGES_RATE = 0.00003503
    SEBI_FEES_RATE = 0.000001
    STAMP_DUTY_RATE = 0.00003
    IPFT_RATE = 0.0000005

    def initialize(position, analysis)
      @position = position.with_indifferent_access
      @a = analysis
    end

    def call
      turnover = (@a[:entry_price] + @a[:ltp]) * @a[:quantity]
      brokerage = BROKERAGE
      transaction_charges = turnover * TRANSACTION_CHARGES_RATE
      sebi_fees = turnover * SEBI_FEES_RATE
      stt = turnover * STT_RATE
      stamp_duty = turnover * STAMP_DUTY_RATE
      ipft = turnover * IPFT_RATE
      gst = (brokerage + transaction_charges + sebi_fees + stt + stamp_duty + ipft) * GST_RATE

      total_charges = brokerage + transaction_charges + sebi_fees + stt + stamp_duty + ipft + gst
      total_charges.round(2)
    end
  end
end
