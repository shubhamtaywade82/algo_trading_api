# frozen_string_literal: true

module Webhooks
  ##
  # AlertsController handles incoming TradingView alerts. It either processes
  # an alert for 'index' or 'stock' instrument types, or returns a keep-alive
  # response for other instrument types. Uses before_actions to keep the
  # create action concise.
  #
  class AlertsController < ApplicationController
    include TelegramNotifiable

    before_action :return_keep_alive, only: :create
    before_action :validate_alert,    only: :create

    # Creates an Alert record if the instrument type is 'index' or 'stock',
    # the alert parameters are valid, and the instrument is found in the DB.
    #
    # @return [JSON] JSON response indicating success or failure.
    #
    def create
      # 1. At this point, we have:
      #    - A relevant instrument type ('index' or 'stock').
      #    - A valid alert (time present).
      # 2. We fetch the instrument or return 404 if not found.
      #
      alert = instrument.alerts.build(alert_params)

      if alert.save
        processor = AlertProcessorFactory.build(alert)
        processor.call
        render json: { message: 'Alert processed successfully', alert: alert }, status: :created
      else
        render json: { error: 'Failed to save alert', details: alert.errors.full_messages },
               status: :unprocessable_entity
      end
    end

    private

    # Returns a "keep-alive" response if the instrument type is neither 'index'
    # nor 'stock'. This is run before :validate_alert in the callback chain.
    #
    # @return [void]
    def return_keep_alive
      return if relevant_instrument_type?

      render json: {
        message: 'Keep-alive request. No instrument lookup performed.'
      }, status: :ok and return
    end

    # Validates the "time" parameter to ensure the alert is not invalid or
    # delayed. If invalid, it returns a 422 (Unprocessable Entity) response and
    # halts the request.
    #
    # @return [void]
    def validate_alert
      return if valid_alert_time?(alert_params)

      render json: { error: 'Invalid or delayed alert' },
             status: :unprocessable_entity and return
    end

    # Determines whether the :time parameter is present and can be parsed.
    #
    # @param alert_hash [Hash] the strong params hash containing `:time`
    # @return [Boolean] true if valid, false otherwise
    #
    def valid_alert_time?(alert_hash)
      parsed_time = begin
        Time.zone.parse(alert_hash[:time])
      rescue StandardError
        nil
      end
      parsed_time.present?
    end

    # Finds or memoizes the associated instrument based on alert_params.
    # Returns 404 if not found.
    #
    # @return [Instrument] the matching instrument or renders a 404
    def instrument
      return @instrument if defined?(@instrument) && @instrument

      type = alert_params[:instrument_type].to_s.downcase
      exch = alert_params[:exchange]

      @instrument =
        case type
        when 'index', 'stock'
          Instrument.find_by!(
            underlying_symbol: alert_params[:ticker],
            segment: segment_from_alert_type(type), # index / equity
            exchange: exch
          )

        when 'futures'
          root = alert_params[:ticker].to_s.gsub(/\d+!$/, '')
          Instrument.where(exchange: exch, segment: 'M')          # commodity
                    .where(underlying_symbol: [root, "#{root}M"]) # main & mini
                    .order(lot_size: :desc)
                    .first
        end

      raise ActiveRecord::RecordNotFound, 'Instrument not found for the given parameters' unless @instrument

      @instrument
    end

    # Checks if the instrument type is 'index' or 'stock', ignoring case.
    #
    # @return [Boolean] true if relevant instrument type, false otherwise
    #
    def relevant_instrument_type?
      %w[index stock futures].include?(alert_params[:instrument_type].to_s.downcase)
    end

    # Converts the incoming `instrument_type` to the segment expected
    # by the Instrument model ('index' remains 'index', 'stock' -> 'equity',
    # else returns instrument_type verbatim).
    #
    # @param instrument_type [String] the incoming type from the alert
    # @return [String] the mapped segment
    #
    def segment_from_alert_type(instrument_type)
      case instrument_type
      when 'index' then 'index'
      when 'stock' then 'equity'
      when 'futures' then 'commodity'
      else instrument_type
      end
    end

    # Strong parameters for alert creation.
    #
    # @return [ActionController::Parameters] sanitized alert params
    def alert_params
      params.require(:alert).permit(
        :ticker,
        :instrument_type,
        :exchange,
        :time,
        :strategy_type,
        :order_type,
        :action,
        :current_position,
        :previous_position,
        :current_price,
        :chart_interval,
        :strategy_name,
        :strategy_id,
        :signal_type
      )
    end
  end
end
