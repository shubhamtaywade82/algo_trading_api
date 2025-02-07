# frozen_string_literal: true

module Webhooks
  class AlertsController < ApplicationController
    def create
      if valid_alert?(alert_params)
        if instrument.nil?
          return render json: { error: 'Instrument not found for the given parameters' },
                        status: :not_found
        end

        # Build the alert with the associated instrument
        alert = instrument.alerts.build(alert_params)
        if alert.save
          processor = AlertProcessorFactory.build(alert)
          processor.call

          render json: { message: 'Alert processed successfully', alert: alert }, status: :created
        else
          render json: { error: 'Failed to save alert', details: alert.errors.full_messages },
                 status: :unprocessable_entity
        end
      else
        render json: { error: 'Invalid or delayed alert' }, status: :unprocessable_entity
      end
    end

    private

    def instrument
      @instrument ||= Instrument.find_by(
        underlying_symbol: alert_params[:ticker],
        segment: segment_from_alert_type(alert_params[:instrument_type]),
        exchange: alert_params[:exchange]
      )
    end

    def alert_params
      params.require(:alert).permit(
        :ticker, :instrument_type, :order_type, :current_position, :previous_position, :strategy_type, :current_price,
        :high, :low, :volume, :time, :chart_interval, :stop_loss, :stop_price, :take_profit, :limit_price,
        :trailing_stop_loss, :strategy_name, :strategy_id, :action, :exchange
      )
    end

    # Map instrument_type to segment
    def segment_from_alert_type(instrument_type)
      case instrument_type
      when 'index' then 'index'
      when 'stock' then 'equity'
      else instrument_type # Default to the given type
      end
    end

    # Validate the alert timing and time range
    def valid_alert?(alert)
      # current_time = Time.zone.now
      alert_time = begin
        Time.zone.parse(alert[:time])
      rescue StandardError
        nil
      end
      # Rails.logger.debug alert_time
      # Rails.logger.debug current_time
      # Rails.logger.debug(current_time - alert_time)
      # (current_time - alert_time) < 70.seconds
      Rails.logger.debug Time.zone.parse(alert[:time])
      alert_time.present?
    end

    # NOTE: NOT USED
    # Check if the alert time is within market hours (9:15 AM to 3:00 PM IST)
    def within_time_range?(alert_time)
      start_time = alert_time.beginning_of_day.change(hour: 9, min: 15)
      end_time = alert_time.beginning_of_day.change(hour: 15, min: 0)
      alert_time.between?(start_time, end_time)
    end
  end
end
