# frozen_string_literal: true

module Alerts
  # Service to resolve an Instrument based on alert parameters from TradingView.
  class InstrumentResolver < ApplicationService
    def initialize(params)
      @params = params
    end

    def call
      type = @params[:instrument_type].to_s.downcase
      exch = @params[:exchange]

      instrument = case type
                   when 'index', 'stock'
                     Instrument.find_by!(
                       underlying_symbol: @params[:ticker],
                       segment: segment_from_alert_type(type),
                       exchange: exch
                     )
                   when 'futures'
                     resolve_futures(exch)
                   end

      raise ActiveRecord::RecordNotFound, 'Instrument not found for the given parameters' unless instrument

      instrument
    end

    private

    def resolve_futures(exch)
      root = @params[:ticker].to_s.gsub(/\d+!$/, '')
      Instrument.where(exchange: exch, segment: 'M')
                .where(underlying_symbol: [root, "#{root}M"])
                .order(lot_size: :desc)
                .first
    end

    def segment_from_alert_type(instrument_type)
      case instrument_type
      when 'index' then 'index'
      when 'stock' then 'equity'
      when 'futures' then 'commodity'
      else instrument_type
      end
    end
  end
end
