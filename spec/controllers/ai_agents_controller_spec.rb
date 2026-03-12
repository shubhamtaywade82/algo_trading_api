# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgentsController, type: :controller do
  # Disable token auth in tests
  before { allow(ENV).to receive(:[]).and_call_original }
  before { allow(ENV).to receive(:[]).with('AI_AGENTS_ACCESS_TOKEN').and_return(nil) }

  describe 'POST #analyze' do
    let(:mock_result) do
      {
        success: true,
        pipeline_results: [],
        final: { output: 'Market is bullish', parsed: { 'bias' => 'bullish' }, agent: 'SupervisorAgent' }
      }
    end

    before { allow(AI::TradeBrain).to receive(:analyze).and_return(mock_result) }

    it 'returns 200 with analysis result' do
      post :analyze, params: { symbol: 'NIFTY' }, format: :json
      expect(response).to have_http_status(:ok)
    end

    it 'calls TradeBrain.analyze with the symbol' do
      expect(AI::TradeBrain).to receive(:analyze).with('NIFTY', candle: '15m')
      post :analyze, params: { symbol: 'NIFTY' }, format: :json
    end

    it 'returns 422 when symbol is missing' do
      post :analyze, params: {}, format: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'POST #propose' do
    let(:valid_proposal) do
      {
        symbol: 'NIFTY', direction: 'CE', strike: 24300,
        entry_price: 62.5, stop_loss: 42.0, target: 110.0,
        quantity: 75, product: 'INTRADAY', confidence: 0.75,
        risk_reward: 2.3, risk_approved: true,
        expiry: (Date.today + 7).to_s, rationale: 'Bullish.'
      }
    end

    let(:mock_result) { { success: true, proposal: valid_proposal, pipeline_results: [] } }

    before { allow(AI::TradeBrain).to receive(:propose).and_return(mock_result) }

    it 'returns 200 with proposal and validation' do
      post :propose, params: { symbol: 'NIFTY' }, format: :json
      json = JSON.parse(response.body)

      expect(response).to have_http_status(:ok)
      expect(json).to have_key('proposal')
      expect(json).to have_key('validation')
      expect(json).to have_key('ready_to_trade')
    end
  end

  describe 'POST #ask' do
    let(:mock_result) { { success: true, answer: 'Trade exited due to stop-loss hit at 14:32 IST.' } }

    before { allow(AI::TradeBrain).to receive(:ask).and_return(mock_result) }

    it 'returns the agent answer' do
      post :ask, params: { question: 'Why did trade exit early?' }, format: :json
      json = JSON.parse(response.body)

      expect(response).to have_http_status(:ok)
      expect(json['answer']).to include('stop-loss')
    end

    it 'returns 422 when question is missing' do
      post :ask, params: {}, format: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'GET #positions' do
    let(:mock_result) { { success: true, answer: 'You have 2 open positions, both profitable.' } }

    before { allow(AI::TradeBrain).to receive(:review_positions).and_return(mock_result) }

    it 'returns position review' do
      get :positions, format: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'authentication' do
    before { allow(ENV).to receive(:[]).with('AI_AGENTS_ACCESS_TOKEN').and_return('secret-token') }

    it 'returns 401 when no token provided' do
      post :analyze, params: { symbol: 'NIFTY' }, format: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 200 when correct token provided' do
      allow(AI::TradeBrain).to receive(:analyze).and_return({ success: true })
      request.headers['Authorization'] = 'Bearer secret-token'
      post :analyze, params: { symbol: 'NIFTY' }, format: :json
      expect(response).to have_http_status(:ok)
    end
  end
end
