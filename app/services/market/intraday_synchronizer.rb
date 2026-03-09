# frozen_string_literal: true

module Market
  # Service to fetch and align intraday data for Spot and multiple Option strikes
  # at the exact same timestamps.
  class IntradaySynchronizer < ApplicationService
    def initialize(symbol: 'NIFTY', date: Time.zone.today, interval: '1', strikes: ['ATM', 'ATM+1', 'ATM-1'])
      @symbol = symbol.upcase
      @date = date.is_a?(String) ? Date.parse(date) : date
      @interval = interval
      @strikes = strikes
    end

    def call
      instrument = find_instrument
      return { error: 'Instrument not found' } unless instrument

      # 1. Fetch Spot Data
      # Dhan intraday requires from_date < to_date
      to_date_val = @date + 1.day
      spot_data = instrument.intraday_ohlc(
        from_date: @date.to_s,
        to_date: to_date_val.to_s,
        interval: @interval
      )
      return { error: "No spot data for #{@date}" } if spot_data.blank? || spot_data['timestamp'].blank?

      # For rolling options, sometimes the 'to_date' needs to be further out if looking for a specific week
      # but let's first try just ensuring we have the right to_date.
      opt_to_date = @date + 30.days

      # 2. Fetch Option Data for each strike and type
      # We create a map: timestamp -> { spot: price, ce_atm: price, pe_atm: price, ... }
      sync_map = {}
      
      # Initialize map with spot data
      spot_data['timestamp'].each_with_index do |ts, i|
        sync_map[ts] = {
          time: Time.zone.at(ts).strftime('%H:%M:%S'),
          spot: {
            o: spot_data['open'][i],
            h: spot_data['high'][i],
            l: spot_data['low'][i],
            c: spot_data['close'][i]
          }
        }
      end

      # Fetch Options
      @strikes.each do |strike_name|
        ['CALL', 'PUT'].each do |type|
          opt_data = Dhan::MarketDataService.new(instrument).rolling_ohlc(
            from_date: @date.to_s,
            to_date: opt_to_date.to_s,
            interval: @interval,
            strike: strike_name,
            option_type: type,
            expiry_code: 1 # Current week
          )
          
          next if opt_data.blank? || opt_data[:timestamp].blank?

          suffix = "#{type == 'CALL' ? 'ce' : 'pe'}_#{strike_name.downcase.gsub('+', 'p').gsub('-', 'm')}"
          
          opt_data[:timestamp].each_with_index do |ts, i|
            if sync_map[ts]
              sync_map[ts][suffix.to_sym] = {
                o: opt_data[:open][i],
                h: opt_data[:high][i],
                l: opt_data[:low][i],
                c: opt_data[:close][i]
              }
            end
          end
          # Prevent rate limit if many strikes
          sleep 0.2
        end
      end

      # Return sorted array of snapshots
      sync_map.sort.map(&:last)
    end

    private

    def find_instrument
      Instrument.find_by(underlying_symbol: @symbol) || Instrument.find_by(symbol_name: @symbol)
    end
  end
end
