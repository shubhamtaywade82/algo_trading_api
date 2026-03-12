# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgentsController, type: :controller do
  # Disable token auth unless specifically testing it
  before { allow(ENV).to receive(:[]).and_call_original }
  before { allow(ENV).to receive(:[]).with('AI_AGENTS_ACCESS_TOKEN').and_return(nil) }

  # Minimal Agents::RunResult mock
  def run_result(output)
    instance_double('Agents::RunResult',
      output:  output,
      context: { current_agent: 'Test', conversation_history: [] }
    )
  end

  describe 'POST #analyze' do
    before do
      allow(AI::TradeBrain).to receive(:analyze).and_return(
        run_result('NIFTY is in an uptrend with bullish bias.')
      )
    end

    it 'returns 200 with output and context' do
      post :analyze, params: { symbol: 'NIFTY' }, format: :json
      json = JSON.parse(response.body)

      expect(response).to have_http_status(:ok)
      expect(json).to have_key('output')
      expect(json).to have_key('context')
    end

    it 'passes symbol and candle to TradeBrain' do
      expect(AI::TradeBrain).to receive(:analyze).with('NIFTY', candle: '5m', context: nil)
      post :analyze, params: { symbol: 'NIFTY', candle: '5m' }, format: :json
    end

    it 'returns 422 when symbol is missing' do
      post :analyze, params: {}, format: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'POST #propose' do
    let(:valid_proposal) do
      {
        'symbol' => 'NIFTY', 'direction' => 'CE', 'strike' => 24300,
        'entry_price' => 62.5, 'stop_loss' => 42.0, 'target' => 110.0,
        'quantity' => 75, 'confidence' => 0.75, 'risk_reward' => 2.3,
        'product' => 'INTRADAY', 'expiry' => (Date.today + 7).to_s,
        'risk_approved' => true
      }
    end

    before do
      allow(AI::TradeBrain).to receive(:propose).and_return({
        result:     run_result('Trade setup generated.'),
        output:     'Trade setup generated.',
        context:    {},
        proposal:   valid_proposal,
        validation: Strategy::Validator.validate(valid_proposal)
      })
    end

    it 'returns 200 with proposal, validation and ready_to_trade flag' do
      post :propose, params: { symbol: 'NIFTY' }, format: :json
      json = JSON.parse(response.body)

      expect(response).to have_http_status(:ok)
      expect(json).to have_key('proposal')
      expect(json).to have_key('validation')
      expect(json).to have_key('ready_to_trade')
    end

    it 'sets ready_to_trade to true when proposal is valid' do
      post :propose, params: { symbol: 'NIFTY' }, format: :json
      json = JSON.parse(response.body)
      expect(json['ready_to_trade']).to be true
    end
  end

  describe 'POST #ask' do
    before do
      allow(AI::TradeBrain).to receive(:ask).and_return(
        run_result('Trade exited due to stop-loss hit at 14:32 IST.')
      )
    end

    it 'returns the agent answer' do
      post :ask, params: { question: 'Why did NIFTY CE exit?' }, format: :json
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
    before do
      allow(AI::TradeBrain).to receive(:review_positions).and_return(
        run_result('You have 2 open positions, both profitable.')
      )
    end

    it 'returns 200 with answer and context' do
      get :positions, format: :json
      json = JSON.parse(response.body)

      expect(response).to have_http_status(:ok)
      expect(json['answer']).to include('profitable')
    end
  end

  describe 'authentication' do
    before { allow(ENV).to receive(:[]).with('AI_AGENTS_ACCESS_TOKEN').and_return('secret-token') }

    it 'returns 401 when no token provided' do
      post :analyze, params: { symbol: 'NIFTY' }, format: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 200 when correct Bearer token provided' do
      allow(AI::TradeBrain).to receive(:analyze).and_return(run_result('ok'))
      request.headers['Authorization'] = 'Bearer secret-token'
      post :analyze, params: { symbol: 'NIFTY' }, format: :json
      expect(response).to have_http_status(:ok)
    end

    it 'returns 401 for wrong token' do
      request.headers['Authorization'] = 'Bearer wrong-token'
      post :analyze, params: { symbol: 'NIFTY' }, format: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
