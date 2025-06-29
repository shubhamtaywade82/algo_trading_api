# spec/requests/webhooks/alerts_controller_spec.rb
require 'rails_helper'

RSpec.describe 'Webhooks::AlertsController', type: :request do
  include AlertParamsHelper

  let(:instrument) { create(:instrument, underlying_symbol: 'NIFTY', segment: 'index', exchange: 'NSE') }
  let(:nify_alert_params) do
    json_fixture('index_alert')
  end
  let(:reliance_alert_params) do
    json_fixture('stock_alert')
  end

  before do
    stub_request(:post, %r{api\.telegram\.org/bot.*?/sendMessage})
      .to_return(status: 200, body: '', headers: {})
    stub_request(:post, 'https://sandbox.dhan.co/v2/optionchain/expirylist')
      .with(
      body: '{"UnderlyingScrip":2885,"UnderlyingSeg":"IDX_I","dhanClientId":"1104216308"}',
      headers: {
        'Accept' => 'application/json',
        'Accept-Encoding' => 'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
        'Access-Token' => ENV.fetch('DHAN_ACCESS_TOKEN', nil),
        'Client-Id' => ENV.fetch('DHAN_CLIENT_ID', nil),
        'Content-Type' => 'application/json',
        'User-Agent' => 'Faraday v1.10.4'
      }
    )
      .to_return(status: 200, body: '', headers: {})
  end

  describe 'POST /webhooks/tradingview' do
    let(:params) { { alert: nify_alert_params } }

    context 'when instrument exists' do
      before { instrument }

      it 'processes the alert successfully' do
        expect do
          post '/webhooks/tradingview', params: params
        end.to change(Alert, :count).by(1)

        expect(response).to have_http_status(:created)
        json = response.parsed_body
        expect(json['message']).to eq('Alert processed successfully')
        expect(json['alert']['ticker']).to eq('NIFTY')
      end
    end

    context 'when instrument does not exist' do
      let(:params) { { alert: reliance_alert_params } }

      it 'returns a not found error' do
        post '/webhooks/tradingview', params: params

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when alert has an invalid time' do
      before { instrument }

      it 'returns an error for invalid alert time' do
        invalid_params = params.deep_dup
        invalid_params[:alert][:time] = 'invalid-time-string'

        post '/webhooks/tradingview', params: invalid_params

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Invalid or delayed alert')
      end
    end

    context 'when alert instrument_type is irrelevant' do
      it 'returns a keep-alive response' do
        keep_alive_params = params.deep_dup
        keep_alive_params[:alert][:instrument_type] = 'crypto'

        post '/webhooks/tradingview', params: keep_alive_params

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['message']).to eq('Keep-alive request. No instrument lookup performed.')
      end
    end
  end
end
