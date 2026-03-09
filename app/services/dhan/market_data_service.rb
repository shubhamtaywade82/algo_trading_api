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

    def historical_ohlc(from_date: nil, to_date: nil, oi: false, expiry_date: nil, strike_price: nil, option_type: nil)
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

      # Add expired option parameters if provided
      params[:expiry_date] = expiry_date if expiry_date
      params[:strike_price] = strike_price if strike_price
      params[:option_type] = option_type if option_type

      # Only include expiry_code for derivative instruments (futures/options)
      # Note: For expired options, expiry_date is usually provided instead.
      params[:expiry_code] = 0 if instrument_code.to_s.match?(/^(FUT|OPT)/) && expiry_date.nil?

      log_debug("Fetching Historical OHLC for Instrument #{@instrument.security_id} with params: #{params.inspect}")
      DhanHQ::Models::HistoricalData.daily(params)
    rescue StandardError => e
      log_error("Failed to fetch Historical OHLC for Instrument #{@instrument.security_id}: #{e.message}")
      nil
    end

    def intraday_ohlc(interval: Instrument::DEFAULT_INTRADAY_INTERVAL, oi: false, from_date: nil, to_date: nil, days: 2, expiry_date: nil, strike_price: nil, option_type: nil)
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

      params = {
        security_id: @instrument.security_id,
        exchange_segment: @instrument.exchange_segment,
        instrument: instrument_code,
        interval: interval_str,
        oi: oi,
        from_date: from_date,
        to_date: to_date_final
      }

      # Add expired option parameters if provided
      params[:expiry_date] = expiry_date if expiry_date
      params[:strike_price] = strike_price if strike_price
      params[:option_type] = option_type if option_type

      log_debug("Fetching Intraday OHLC for Instrument #{@instrument.security_id} with params: #{params.inspect}")
      response = DhanHQ::Models::HistoricalData.intraday(params)
      
      data = response.is_a?(Hash) ? response.with_indifferent_access : {}
      log_debug("Raw Intraday OHLC response: #{data.keys.inspect}")
      data
    rescue StandardError => e
      log_error("Failed to fetch Intraday OHLC for Instrument #{@instrument.security_id}: #{e.message}")
      nil
    end

    def rolling_ohlc(from_date:, to_date:, interval: '5', strike: 'ATM', option_type: 'CALL', expiry_flag: 'WEEK', expiry_code: 1)
      # The DhanHQ gem doesn't have a built-in method for /charts/rollingoption yet,
      # so we use the underlying Resource client to make the POST request.
      resource = DhanHQ::Models::HistoricalData.resource
      params = {
        exchange_segment: 'NSE_FNO',
        security_id: @instrument.security_id.to_s, # Underlying (e.g., 13 for NIFTY)
        instrument: 'OPTIDX',
        expiry_flag: expiry_flag,
        expiry_code: expiry_code,
        strike: strike,
        drv_option_type: option_type,
        interval: interval.to_s,
        from_date: from_date.to_s,
        to_date: to_date.to_s,
        required_data: ['open', 'high', 'low', 'close', 'volume', 'oi']
      }

      log_debug("Fetching Rolling Option OHLC for #{@instrument.underlying_symbol} with params: #{params.inspect}")
      
      # resource.post calls /v2/charts + endpoint
      response = resource.post('/rollingoption', params: params)
      
      # Debug log the full response
      log_debug("Raw Rolling Option OHLC response: #{response.inspect}")
      
      # Ensure it's a Hash with indifferent access
      full_data = response.is_a?(Hash) ? response.with_indifferent_access : {}
      
      # The API returns {"data" => {"ce" => {...}, "pe" => {...}}}
      # We extract the specific type requested (ce or pe)
      type_key = option_type.to_s.upcase == 'CALL' ? 'ce' : 'pe'
      data = full_data.dig(:data, type_key) || {}
      
      if data[:open].blank?
        log_warn("Rolling Option OHLC returned empty data for #{@instrument.underlying_symbol} #{option_type}")
      end
      
      data
    rescue StandardError => e
      log_error("Failed to fetch Rolling Option OHLC: #{e.message}")
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
