# frozen_string_literal: true

require 'csv'

module Trading
  # Resolve derivative contracts using the Dhan scrip master CSV.
  # This provides a deterministic lookup without hitting the live Dhan API.
  class DerivativeResolver
    Result = Struct.new(
      :security_id,
      :exchange_segment,
      :trading_symbol,
      :lot_size,
      keyword_init: true
    )

    SCRIP_PATH = Rails.root.join('tmp/dhan_scrip_master.csv')
    CACHE = {}
    CACHE_MUTEX = Mutex.new

    def self.load_index!
      return if CACHE.any?

      CACHE_MUTEX.synchronize do
        return if CACHE.any?

        Rails.logger.info "Loading Dhan scrip master index from #{SCRIP_PATH}..."
        CSV.foreach(SCRIP_PATH, headers: true) do |row|
          next unless row['SEGMENT'] == 'D' # Only derivatives

          key = [
            row['UNDERLYING_SYMBOL'],
            row['SM_EXPIRY_DATE'],
            row['STRIKE_PRICE'].to_f.to_i,
            row['OPTION_TYPE']
          ].join(':')

          CACHE[key] = {
            security_id: row['SECURITY_ID'],
            exchange_segment: "#{row['EXCH_ID']}_#{row['SEGMENT'] == 'D' ? 'FNO' : 'EQ'}", # Simplified mapping
            trading_symbol: row['SYMBOL_NAME'],
            lot_size: row['LOT_SIZE'].to_i
          }
        end
        Rails.logger.info "Dhan scrip master index loaded: #{CACHE.size} contracts"
      end
    end

    def initialize(symbol:, expiry:, strike:, option_type:)
      @symbol = symbol.upcase
      @expiry = expiry # Expecting YYYY-MM-DD
      @strike = strike.to_i
      @option_type = option_type.upcase
    end

    def call
      validate!

      # Try cache first
      self.class.load_index! if CACHE.empty?
      
      key = [@symbol, @expiry, @strike, @option_type].join(':')
      data = CACHE[key]

      # Fallback to manual scan if not found in cache (e.g. if index failed to load)
      data ||= find_in_csv if CACHE.empty?

      raise "Contract not found for #{@symbol} #{@expiry} #{@strike} #{@option_type}" unless data

      Result.new(data)
    end

    private

    def validate!
      raise 'Invalid symbol' unless %w[NIFTY BANKNIFTY SENSEX FINNIFTY MIDCPNIFTY].include?(@symbol)
      raise 'Invalid option_type' unless %w[CE PE].include?(@option_type)
      raise 'Invalid strike' if @strike <= 0
      raise 'Invalid expiry format (expected YYYY-MM-DD)' unless @expiry =~ /^\d{4}-\d{2}-\d{2}$/
    end

    def find_in_csv
      CSV.foreach(SCRIP_PATH, headers: true) do |row|
        next unless row['UNDERLYING_SYMBOL'] == @symbol
        next unless row['SM_EXPIRY_DATE'] == @expiry
        next unless row['STRIKE_PRICE'].to_f.to_i == @strike
        next unless row['OPTION_TYPE'] == @option_type

        return {
          security_id: row['SECURITY_ID'],
          exchange_segment: row['EXCH_ID'] == 'NSE' ? 'NSE_FNO' : 'BSE_FNO',
          trading_symbol: row['SYMBOL_NAME'],
          lot_size: row['LOT_SIZE'].to_i
        }
      end
      nil
    end
  end
end
