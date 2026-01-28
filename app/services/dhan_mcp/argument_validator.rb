# frozen_string_literal: true

module DhanMcp
  class ArgumentValidator
    EXCHANGE_SEGMENTS = %w[
      IDX_I NSE_EQ NSE_FNO BSE_EQ NSE_CURRENCY MCX_COMM BSE_CURRENCY BSE_FNO
    ].freeze

    INTRADAY_INTERVALS = %w[1 5 15 25 60].freeze

    DATE_ONLY = /\A\d{4}-\d{2}-\d{2}\z/
    DATE_TIME = /\A\d{4}-\d{2}-\d{2}(\s+\d{2}:\d{2}:\d{2})?\z/

    def self.validate(tool_name, args)
      new(tool_name, symbolize(args)).validate
    end

    def self.symbolize(hash)
      return {} if hash.nil? || !hash.respond_to?(:to_h)

      hash.to_h.transform_keys { |k| k.to_s.dup.force_encoding('UTF-8').to_sym }
    end

    def initialize(tool_name, args)
      @tool_name = tool_name.to_s
      @args = args || {}
    end

    def validate
      case @tool_name
      when 'get_holdings', 'get_positions', 'get_fund_limits', 'get_order_list', 'get_edis_inquiry'
        reject_extra_keys([])
      when 'get_order_by_id'
        validate_required(%i[order_id]) { reject_blank_string(:order_id) }
      when 'get_order_by_correlation_id'
        validate_required(%i[correlation_id]) { reject_blank_string(:correlation_id) }
      when 'get_trade_book'
        validate_required(%i[order_id]) { reject_blank_string(:order_id) }
      when 'get_trade_history'
        validate_required(%i[from_date to_date]) do
          reject_blank_string(:from_date) || reject_date_format(:from_date) ||
            reject_blank_string(:to_date) || reject_date_format(:to_date) ||
            reject_date_range_today_and_last_trading_day ||
            reject_non_negative_int(:page_number)
        end
      when 'get_instrument', 'get_market_ohlc', 'get_expiry_list'
        validate_required(%i[exchange_segment symbol]) do
          reject_blank_string(:exchange_segment) || reject_exchange_segment ||
            reject_blank_string(:symbol)
        end
      when 'get_historical_daily_data'
        validate_required(%i[exchange_segment symbol from_date to_date]) do
          reject_blank_string(:exchange_segment) || reject_exchange_segment ||
            reject_blank_string(:symbol) ||
            reject_blank_string(:from_date) || reject_date_format(:from_date) ||
            reject_blank_string(:to_date) || reject_date_format(:to_date) ||
            reject_date_range_today_and_last_trading_day
        end
      when 'get_intraday_minute_data'
        validate_required(%i[exchange_segment symbol from_date to_date]) do
          reject_blank_string(:exchange_segment) || reject_exchange_segment ||
            reject_blank_string(:symbol) ||
            reject_blank_string(:from_date) || reject_date_time(:from_date) ||
            reject_blank_string(:to_date) || reject_date_time(:to_date) ||
            reject_date_range_today_and_last_trading_day ||
            reject_interval
        end
      when 'get_option_chain'
        validate_required(%i[exchange_segment symbol expiry]) do
          reject_blank_string(:exchange_segment) || reject_exchange_segment ||
            reject_blank_string(:symbol) ||
            reject_blank_string(:expiry) || reject_date_format(:expiry)
        end
      end
    end

    private

    def validate_required(keys)
      missing = keys.reject { |k| @args.key?(k) }
      return "Missing required argument(s): #{missing.join(', ')}" if missing.any?

      yield
    end

    def reject_extra_keys(allowed)
      extra = @args.keys - allowed
      return nil if extra.empty?

      "Unexpected argument(s): #{extra.join(', ')}. This tool accepts no arguments."
    end

    def reject_blank_string(key)
      val = @args[key]
      return nil if val.present? && val.to_s.strip != ''

      "#{key} must be non-empty."
    end

    def reject_exchange_segment
      seg = @args[:exchange_segment].to_s.strip
      return nil if EXCHANGE_SEGMENTS.include?(seg)

      "exchange_segment must be one of: #{EXCHANGE_SEGMENTS.join(', ')}."
    end

    def reject_date_format(key)
      val = @args[key].to_s.strip
      return nil if val.match?(DATE_ONLY)

      "#{key} must be YYYY-MM-DD."
    end

    def reject_date_time(key)
      val = @args[key].to_s.strip
      return nil if val.match?(DATE_TIME)

      "#{key} must be YYYY-MM-DD or YYYY-MM-DD HH:MM:SS."
    end

    def reject_non_negative_int(key)
      return nil unless @args.key?(key)

      v = @args[key]
      return nil if v.nil?

      i = v.to_i
      return nil if i >= 0 && (v.is_a?(Integer) || v.to_s.strip == i.to_s)

      "#{key} must be a non-negative integer."
    end

    def reject_interval
      return nil unless @args.key?(:interval)

      iv = @args[:interval].to_s.strip
      return nil if iv.empty? || INTRADAY_INTERVALS.include?(iv)

      "interval must be one of: #{INTRADAY_INTERVALS.join(', ')}."
    end

    def reject_date_range_today_and_last_trading_day
      to_d = parse_date(@args[:to_date])
      from_d = parse_date(@args[:from_date])
      return nil unless to_d && from_d

      today = Time.zone.today
      return "to_date must be today (#{today})." unless to_d == today

      expected_from = MarketCalendar.last_trading_day(from: to_d - 1)
      return nil if from_d == expected_from

      "from_date must be the last trading day before to_date (#{expected_from})."
    end

    def parse_date(val)
      return nil if val.blank?

      str = val.to_s.strip.split(/\s+/).first
      Date.parse(str)
    rescue ArgumentError
      nil
    end
  end
end
