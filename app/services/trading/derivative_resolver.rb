# frozen_string_literal: true

module Trading
  # Resolve derivative contracts to their Dhan tradable identifiers.
  #
  # Reads the `derivatives` table, which `bin/rails import:instruments` populates
  # from the same scrip master this used to parse itself. That import is the
  # app's inventory of contracts and every other lookup already goes through it
  # (AlertProcessors::Index#fetch_derivative, InstrumentUtils, Orders::Manager,
  # Paper::Positions, Dhan::WS::FeedListener) — this was the one caller that did
  # not.
  #
  # It previously built a ~400k-entry Hash out of tmp/dhan_scrip_master.csv at
  # boot. That file is InstrumentsImport::Fetcher's 24-hour *download cache*,
  # not a data file: it is absent on a fresh container, so the index failed to
  # load on every deploy that had not just imported, and the in-memory copy was
  # never invalidated afterwards, so a re-import could not correct a process
  # that had already read stale expiries.
  class DerivativeResolver
    Result = Struct.new(
      :security_id,
      :exchange_segment,
      :trading_symbol,
      :lot_size,
      keyword_init: true
    )

    INDEX_SYMBOLS = %w[NIFTY BANKNIFTY SENSEX FINNIFTY MIDCPNIFTY].freeze
    OPTION_TYPES = %w[CE PE].freeze

    def initialize(symbol:, expiry:, strike:, option_type:)
      @symbol = symbol.to_s.upcase
      @expiry = expiry # Expecting YYYY-MM-DD
      @strike = strike.to_i
      @option_type = option_type.to_s.upcase
    end

    def call
      validate!

      derivative = find_contract
      raise not_found_message unless derivative

      Result.new(
        security_id: derivative.security_id,
        # The model's own mapping, so this agrees with every other call site
        # rather than reimplementing EXCH_ID + segment string juggling.
        exchange_segment: derivative.exchange_segment,
        trading_symbol: derivative.symbol_name,
        lot_size: derivative.lot_size
      )
    end

    private

    def find_contract
      Derivative.find_by(
        underlying_symbol: @symbol,
        expiry_date: @expiry,
        strike_price: @strike,
        option_type: @option_type
      )
    end

    def validate!
      raise 'Invalid symbol' unless INDEX_SYMBOLS.include?(@symbol)
      raise 'Invalid option_type' unless OPTION_TYPES.include?(@option_type)
      raise 'Invalid strike' if @strike <= 0
      raise 'Invalid expiry format (expected YYYY-MM-DD)' unless /^\d{4}-\d{2}-\d{2}$/.match?(@expiry)
    end

    # An empty table and a genuinely unknown contract look identical to the
    # caller otherwise, and they need opposite fixes.
    def not_found_message
      base = "Contract not found for #{@symbol} #{@expiry} #{@strike} #{@option_type}"
      return base if Derivative.exists?

      "#{base} (no derivatives imported — run `bin/rails import:instruments`)"
    end
  end
end
