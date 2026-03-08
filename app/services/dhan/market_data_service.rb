# frozen_string_literal: true

module Dhan
  # Service for fetching market data from DhanHQ API for a specific instrument.
  class MarketDataService < ApplicationService
    def initialize(instrument)
      @instrument = instrument
    end

    def fetch_option_chain(expiry = nil)
      expiry ||= expiry_list.first
      response = DhanHQ::Models::OptionChain.fetch(
        underlying_scrip: @instrument.security_id.to_i,
        underlying_seg: @instrument.exchange_segment,
        expiry: expiry
      )
      last_price, oc_data = option_chain_extract(response)
      return nil unless oc_data

      filtered_data = filter_option_chain_data(oc_data)
      { last_price: last_price, oc: filtered_data }
    rescue StandardError => e
      log_error("Failed to fetch Option Chain for Instrument #{@instrument.security_id}: #{e.message}")
      nil
    end

    def ltp
      payload = { @instrument.exchange_segment => [@instrument.security_id.to_i] }
      log_debug("Fetching LTP for Instrument #{@instrument.security_id} (#{@instrument.exchange_segment})")

      response = DhanHQ::Models::MarketFeed.ltp(payload)
      extract_field_from_feed(response, :last_price)
    rescue StandardError => e
      log_error("Failed to fetch LTP for Instrument #{@instrument.security_id}: #{e.message}")
      nil
    end

    def ohlc
      payload = { @instrument.exchange_segment => [@instrument.security_id.to_i] }
      log_debug("Fetching OHLC for Instrument #{@instrument.security_id} (#{@instrument.exchange_segment})")

      response = DhanHQ::Models::MarketFeed.ohlc(payload)
      extract_security_data(response)
    rescue StandardError => e
      log_error("Failed to fetch OHLC for Instrument #{@instrument.security_id}: #{e.message}")
      nil
    end

    def depth
      payload = { @instrument.exchange_segment => [@instrument.security_id.to_i] }
      log_debug("Fetching Depth for Instrument #{@instrument.security_id} (#{@instrument.exchange_segment})")

      response = DhanHQ::Models::MarketFeed.quote(payload)
      extract_security_data(response)
    rescue StandardError => e
      log_error("Failed to fetch Depth for Instrument #{@instrument.security_id}: #{e.message}")
      nil
    end

    def historical_ohlc(from_date: nil, to_date: nil, oi: false)
      instrument_code = @instrument.resolve_instrument_code
      to_date_final = to_date.presence&.to_s || Time.zone.today.to_s
      from_date_final = from_date.presence&.to_s || (Time.zone.today - 30).to_s
      params = {
        security_id: @instrument.security_id,
        exchange_segment: @instrument.exchange_segment,
        instrument: instrument_code,
        oi: oi,
        from_date: from_date_final,
        to_date: to_date_final
      }

      # Only include expiry_code for derivative instruments (futures/options)
      params[:expiry_code] = 0 if instrument_code.to_s.match?(/^(FUT|OPT)/)

      log_debug("Fetching Historical OHLC for Instrument #{@instrument.security_id} with params: #{params.inspect}")
      DhanHQ::Models::HistoricalData.daily(params)
    rescue StandardError => e
      log_error("Failed to fetch Historical OHLC for Instrument #{@instrument.security_id}: #{e.message}")
      nil
    end

    def intraday_ohlc(interval: Instrument::DEFAULT_INTRADAY_INTERVAL, oi: false, from_date: nil, to_date: nil, days: 2)
      today = Time.zone.today
      to_date_final = to_date.presence&.to_s&.strip.presence || today.to_s

      from_date ||= if defined?(MarketCalendar) && MarketCalendar.respond_to?(:from_date_for_last_n_trading_days)
                      MarketCalendar.from_date_for_last_n_trading_days(today, days).to_s
                    else
                      (today - days).to_s
                    end

      interval_str = interval.to_s.strip.presence || Instrument::DEFAULT_INTRADAY_INTERVAL
      interval_str = Instrument::DEFAULT_INTRADAY_INTERVAL unless Instrument::INTRADAY_INTERVALS.include?(interval_str)
      instrument_code = @instrument.resolve_instrument_code

      DhanHQ::Models::HistoricalData.intraday(
        security_id: @instrument.security_id,
        exchange_segment: @instrument.exchange_segment,
        instrument: instrument_code,
        interval: interval_str,
        oi: oi,
        from_date: from_date,
        to_date: to_date_final
      )
    rescue StandardError => e
      log_error("Failed to fetch Intraday OHLC for Instrument #{@instrument.security_id}: #{e.message}")
      nil
    end

    def expiry_list
      DhanHQ::Models::OptionChain.fetch_expiry_list(
        underlying_scrip: @instrument.security_id.to_i,
        underlying_seg: @instrument.exchange_segment
      )
    end

    private

    def extract_field_from_feed(response, field)
      security_data = extract_security_data(response)
      return nil unless security_data

      # Common field names for LTP/Price across different API responses
      fields = [field, :ltp, 'last_price', 'ltp']
      value = nil
      fields.each do |f|
        value = security_data[f] || security_data[f.to_s]
        break if value
      end

      return value if value

      log_warn("No #{field} found for Instrument #{@instrument.security_id}. Keys: #{security_data.keys.inspect}")
      nil
    end

    def extract_security_data(response)
      data = response[:data] || response['data'] || response
      return nil unless data

      segment_data = data[@instrument.exchange_segment] || data[@instrument.exchange_segment.to_sym]
      unless segment_data
        log_warn("No segment data for #{@instrument.exchange_segment} in response for #{@instrument.security_id}")
        return nil
      end

      security_data = segment_data[@instrument.security_id.to_s] || segment_data[@instrument.security_id.to_i]
      unless security_data
        log_warn("No security data for #{@instrument.security_id} in segment #{@instrument.exchange_segment}")
        return nil
      end

      security_data
    end

    def option_chain_extract(response)
      data = response.is_a?(Hash) ? (response['data'] || response) : response
      return [nil, nil] unless data

      last_price = data.is_a?(Hash) ? (data['last_price'] || data[:last_price]) : nil
      oc_data = data.is_a?(Hash) ? (data['oc'] || data[:oc]) : nil
      [last_price, oc_data]
    end

    def filter_option_chain_data(data)
      data.select { |_strike, option_data| option_has_tradable_legs?(option_data) }
    end

    def option_has_tradable_legs?(option_data)
      return false unless option_data.is_a?(Hash)

      call_data = option_data['ce'] || option_data[:ce]
      put_data = option_data['pe'] || option_data[:pe]
      leg_has_positive_values?(call_data) || leg_has_positive_values?(put_data)
    end

    def leg_has_positive_values?(leg_data)
      return false unless leg_data.is_a?(Hash)

      tradable = leg_data.except('implied_volatility', :implied_volatility).values
      tradable.any? { |v| numeric_value?(v) && v.to_f.positive? }
    end

    def numeric_value?(value)
      value.is_a?(Numeric) || value.to_s.match?(/\A-?\d+(\.\d+)?\z/)
    end
  end
end
