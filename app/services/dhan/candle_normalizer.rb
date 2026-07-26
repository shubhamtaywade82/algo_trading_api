# frozen_string_literal: true

module Dhan
  # Normalizes DhanHQ historical/intraday chart responses into the columnar
  # OHLC hash this application has always consumed.
  #
  # DhanHQ >= 3.0 changed `Models::HistoricalData.daily/.intraday` to return an
  # Array of per-candle hashes (`[{ timestamp:, open:, high:, low:, close:,
  # volume: }, ...]`). Older versions returned the raw columnar payload
  # (`{ "open" => [...], "close" => [...], ... }`).
  #
  # Consumers across this app index by column (`bars['close'].last`,
  # `spot_data['timestamp'].each_with_index`), and `Market::CandleLoader`
  # accepts the columnar shape too, so we convert back at the SDK boundary
  # rather than rewriting every call site.
  #
  # Timestamps are emitted as epoch integers, matching the pre-3.0 payload —
  # callers pass them straight to `Time.zone.at`.
  module CandleNormalizer
    COLUMNS = %w[timestamp open high low close volume open_interest].freeze

    module_function

    # @param response [Array<Hash>, Hash, nil] raw SDK response
    # @return [HashWithIndifferentAccess, nil] columnar OHLC, or nil when blank
    def columnar(response)
      return nil if response.blank?
      # Already columnar (pre-3.0 shape, or an unrecognized payload passed through
      # untouched by the SDK's own normalizer) - hand it back unchanged.
      return response.with_indifferent_access if response.is_a?(Hash)
      return nil unless response.is_a?(Array)

      rows = response.select { |row| row.is_a?(Hash) }
      rows.empty? ? nil : build_columns(rows)
    end

    # @param rows [Array<Hash>] per-candle hashes
    # @return [HashWithIndifferentAccess]
    def build_columns(rows)
      COLUMNS.each_with_object({}.with_indifferent_access) do |column, out|
        values = rows.map { |row| row[column.to_sym] || row[column] }
        # `open_interest` is only present when the caller requested oi.
        next if column == 'open_interest' && values.all?(&:nil?)

        out[column] = column == 'timestamp' ? values.map { |v| epoch(v) } : values
      end
    end

    # Coerces a candle timestamp to an epoch integer.
    #
    # The SDK maps numeric timestamps through `Time.at`; anything else (an ISO
    # string, or nil) is passed through as-is.
    def epoch(value)
      case value
      when Time, DateTime then value.to_i
      when Numeric then value.to_i
      when String then parse_epoch(value)
      end
    end

    def parse_epoch(value)
      Time.zone.parse(value)&.to_i
    rescue ArgumentError, TypeError
      nil
    end
  end
end
