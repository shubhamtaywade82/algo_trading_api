# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'

RSpec.describe 'Webhooks::AlertsController', type: :request do
  let(:valid_alert_params) do
    {
      alert: {
        ticker: 'NIFTY',
        instrument_type: 'index',
        order_type: 'LIMIT',
        current_position: 'long',
        previous_position: 'neutral',
        strategy_type: 'intraday',
        current_price: 22_000.50,
        high: 22_100.75,
        low: 21_950.25,
        volume: 1000,
        time: Time.zone.now.iso8601,
        chart_interval: '5m',
        stop_loss: 21_900,
        stop_price: 21_890,
        take_profit: 22_150,
        limit_price: 22_100,
        trailing_stop_loss: 50,
        strategy_name: 'Breakout Strategy',
        strategy_id: 'STRAT1234',
        action: 'buy',
        exchange: 'NSE'
      }
    }
  end

  # let!(:instrument) { create(:instrument, underlying_symbol: 'NIFTY', segment: 'index', exchange: 'NSE') }

  describe 'POST /webhooks/tradingview' do
    context 'with valid alert data' do
      it 'creates an alert and processes it' do
        post '/webhooks/tradingview', params: valid_alert_params, as: :json

        expect(response).to have_http_status(:created)
        expect(json['message']).to eq('Alert processed successfully')
        expect(json['alert']['ticker']).to eq('NIFTY')
      end
    end

    context 'with missing instrument' do
      before { instrument.destroy } # Ensure no instrument exists

      it 'returns an error when instrument is not found' do
        post '/webhooks/tradingview', params: valid_alert_params, as: :json

        expect(response).to have_http_status(:not_found)
        expect(json['error']).to eq('Instrument not found for the given parameters')
      end
    end

    context 'with invalid alert data' do
      let(:invalid_alert_params) { { alert: { ticker: nil, time: nil } } }

      it 'returns an error for invalid data' do
        post '/webhooks/tradingview', params: invalid_alert_params, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json['error']).to eq('Invalid or delayed alert')
      end
    end

    context 'when alert saving fails' do
      it 'returns an error message' do
        post '/webhooks/tradingview', params: valid_alert_params, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json['error']).to eq('Failed to save alert')
        expect(json['details']).to include('Database error')
      end
    end
  end
end
