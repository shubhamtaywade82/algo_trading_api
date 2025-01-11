# frozen_string_literal: true

# app/services/parsers/live_order_parser.rb
module Parsers
  class LiveOrderParser
    REQUIRED_FIELDS = %w[
      Exchange Segment Source SecurityId ClientId ExchOrderNo OrderNo Product
      TxnType OrderType Validity RemainingQuantity Quantity TradedQty Price
      TriggerPrice TradedPrice AvgTradedPrice OrderDateTime ExchOrderTime
      LastUpdatedTime Remarks Status Symbol DisplayName Isin
    ].freeze

    def initialize(raw_data)
      @raw_data = raw_data
      @parsed_data = {}
    end

    def parse
      extract_data
      validate_data
      @parsed_data
    rescue StandardError => e
      Rails.logger.error("LiveOrderParser failed: #{e.message}")
      nil
    end

    private

    attr_reader :raw_data

    def extract_data
      @parsed_data = raw_data['Data'].slice(*REQUIRED_FIELDS)
    end

    def validate_data
      missing_fields = REQUIRED_FIELDS - @parsed_data.keys
      raise "Missing required fields: #{missing_fields.join(', ')}" unless missing_fields.empty?
    end
  end
end
