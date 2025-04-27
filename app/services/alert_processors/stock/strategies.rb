# frozen_string_literal: true

module AlertProcessors
  class Stock < Base
    module Strategies
      # Shared API for all strategies
      # -----------------------------------------------------------
      # Super-light objects containing ONLY the bits that differ
      # between intraday / swing / long-term.
      # -----------------------------------------------------------
      class Base
        attr_reader :processor, :alert, :instrument, :current_qty, :ltp

        def initialize(processor)
          @processor   = processor
          @alert       = processor.alert
          @instrument  = processor.instrument
          @current_qty = processor.fetch_current_net_quantity
          @ltp         = processor.ltp
        end

        # each subclass must implement:
        #   #product_type            → CNC / INTRA
        #   #allowed_signal?(type)   → true / false
        #   #utilisation_fraction    → 0.30 etc.
      end

      # ────────────────────────────────────────────────────────────
      class Intraday < Base
        def product_type            = Dhanhq::Constants::INTRA
        # long + short
        def allowed_signal?(_type)  = true
        # 30 % of free cash
        def utilisation_fraction    = 0.30
      end

      class Swing < Base
        def product_type            = Dhanhq::Constants::CNC
        def allowed_signal?(type)   = !type.to_s.start_with?('short_')
        def utilisation_fraction    = 0.30
      end

      # long-term == swing rules
      class LongTerm < Swing; end
    end
  end
end
