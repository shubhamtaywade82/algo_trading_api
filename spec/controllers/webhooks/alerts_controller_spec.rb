# frozen_string_literal: true

# spec/requests/webhooks/alerts_controller_spec.rb
require 'rails_helper'

RSpec.describe 'Webhooks::AlertsController', type: :request do
  include AlertParamsHelper
  let(:instrument) { create(:instrument) }

  describe 'POST /webhooks/tradingview' do
    let(:params) { { alert: valid_alert_params } }

    context 'when instrument exists' do
      before { instrument }

      it 'processes the alert successfully' do
        post '/webhooks/tradingview', params: params

        expect(response).to have_http_status(:created)
        expect(Alert.count).to eq(1)
        # expect(Alert.last.status).to eq('processed')
      end
    end

    context 'when instrument does not exist' do
      before { instrument.destroy }

      it 'returns a not found error' do
        post '/webhooks/tradingview', params: params

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body['error']).to eq('Instrument not found for the given parameters')
      end
    end

    context 'when alert is invalid' do
      before { instrument }
      it 'returns an error for delayed alert' do
        delayed_params = params.deep_dup
        delayed_params[:alert][:time] = 2.minutes.ago

        post '/webhooks/tradingview', params: delayed_params

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Invalid or delayed alert')
      end
    end
  end
end
