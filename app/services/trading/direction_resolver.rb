# frozen_string_literal: true

module Trading
  # Resolves CE vs PE direction from VWAP + OI confirmation.
  # Both underlying price bias and option OI bias must agree.
  class DirectionResolver < ApplicationService
    Result = Struct.new(:direction, :reason, :vwap, :oi_bias, :price_bias, keyword_init: true)

    def initialize(spot:, candles:, option_chain:)
      @spot         = spot.to_f
      @candles      = candles
      @option_chain = option_chain
    end

    def call
      vwap = calculate_vwap
      price_bias = @spot > vwap ? :bullish : :bearish
      oi_bias = calculate_oi_bias

      direction =
        if price_bias == :bullish && oi_bias == :bullish
          'CE'
        elsif price_bias == :bearish && oi_bias == :bearish
          'PE'
        end

      reason = direction ? "#{price_bias} price + #{oi_bias} OI" : "No confirmation: price=#{price_bias} oi=#{oi_bias}"

      Result.new(
        direction: direction,
        reason: reason,
        vwap: vwap.round(2),
        oi_bias: oi_bias,
        price_bias: price_bias
      )
    end

    private

    def calculate_vwap
      total_vol = @candles.sum { |c| c[:volume].to_f }
      return @candles.map { |c| c[:close].to_f }.sum / @candles.size.to_f if total_vol.zero?

      @candles.sum { |c| c[:close].to_f * c[:volume].to_f } / total_vol
    end

    # chain[:oc] is Hash[strike_string => { "ce" => { "oi" => N }, "pe" => { "oi" => N } }]
    def calculate_oi_bias
      oc = @option_chain.is_a?(Hash) ? (@option_chain[:oc] || @option_chain['oc']) : nil
      return :neutral if oc.blank?

      ce_oi = 0
      pe_oi = 0

      oc.each_value do |strike_data|
        row = strike_data.is_a?(Hash) ? strike_data.with_indifferent_access : {}
        ce_oi += row.dig('ce', 'oi').to_i
        pe_oi += row.dig('pe', 'oi').to_i
      end

      return :neutral if ce_oi.zero? && pe_oi.zero?

      if pe_oi > ce_oi
        :bullish
      elsif ce_oi > pe_oi
        :bearish
      else
        :neutral
      end
    end
  end
end

