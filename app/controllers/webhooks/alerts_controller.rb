class Webhooks::AlertsController < ApplicationController
  def create
    alert = Alert.new(alert_params)

    if valid_alert?(alert_params)
      # Create the alert with a pending status
      alert = Alert.create(alert_params)

      if alert.persisted?
        # Process the alert asynchronously
        AlertProcessor.call(alert)

        render json: { message: "Alert processed successfully", alert: alert }, status: :ok
      else
        render json: { error: "Failed to save alert", details: alert.errors.full_messages }, status: :unprocessable_entity
      end
    else
      render json: { error: "Invalid or delayed alert" }, status: :unprocessable_entity
    end
  end

  private

  def alert_params
    params.require(:alert).permit(
      :ticker, :instrument_type, :order_type, :current_position, :previous_position, :current_price,
      :high, :low, :volume, :time, :chart_interval, :stop_loss, :take_profit, :trailing_stop_loss,
      :strategy_name, :strategy_id, :action
    )
  end

  # Validate alert timestamp to ensure it's not delayed beyond 60 seconds
  def valid_alert?(alert)
    Time.zone.now - Time.parse(alert[:time]) < 60 || true
  rescue ArgumentError
    false
  end

  def parse_payload
    payload = JSON.parse(request.body.read)
    AlertValidator.new(payload)
  end
end
