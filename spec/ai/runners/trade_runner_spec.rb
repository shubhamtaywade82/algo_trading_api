# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AI::Runners::TradeRunner do
  let(:market_output) do
    '{"symbol":"NIFTY","bias":"bullish","trend":"uptrend","volatility":"normal",' \
    '"key_levels":{"support":24100,"resistance":24450},"vix":13.5,"rsi":58.2,' \
    '"reason":"Strong uptrend.","confidence":0.72}'
  end

  let(:options_output) do
    '{"symbol":"NIFTY","expiry":"2025-04-03","iv_rank":38.2,"pcr":1.15,' \
    '"oi_bias":"put_writing","smart_money":"neutral","premium_signal":"buy",' \
    '"recommended_direction":"CE","reason":"Put writing dominant.","confidence":0.68}'
  end

  let(:planner_output) do
    '{"symbol":"NIFTY","direction":"CE","strike":24300,"expiry":"2025-04-03",' \
    '"entry_price":62.5,"stop_loss":42.0,"target":110.0,"quantity":75,' \
    '"product":"INTRADAY","rationale":"Bullish setup.","confidence":0.72,"risk_reward":2.3}'
  end

  let(:risk_output) do
    '{"approved":true,"risk_score":0.35,"capital_ok":true,"daily_loss_ok":true,' \
    '"position_conflict":false,"reasons":[],"adjusted_quantity":null,"adjusted_stop_loss":null}'
  end

  def mock_llm_sequence(*outputs)
    client = instance_double(OpenAI::Client)
    allow(Openai::Client).to receive(:instance).and_return(client)

    responses = outputs.map do |text|
      { 'choices' => [{ 'message' => { 'content' => text, 'tool_calls' => nil } }] }
    end

    allow(client).to receive(:chat).and_return(*responses)
  end

  describe '.run' do
    before do
      mock_llm_sequence(market_output, options_output, planner_output, risk_output)
    end

    it 'returns a proposal hash' do
      result = described_class.run('Generate a NIFTY trade setup')
      expect(result[:proposal]).to be_a(Hash)
    end

    it 'extracts the symbol and direction from the planner agent' do
      result   = described_class.run('Generate a NIFTY trade setup')
      proposal = result[:proposal]

      expect(proposal[:symbol]).to eq('NIFTY')
      expect(proposal[:direction]).to eq('CE')
      expect(proposal[:strike]).to eq(24300)
    end

    it 'includes risk approval status' do
      result = described_class.run('Generate a NIFTY trade setup')
      expect(result[:proposal][:risk_approved]).to be true
    end

    it 'marks pipeline as successful' do
      result = described_class.run('Generate a NIFTY trade setup')
      expect(result[:success]).to be true
    end
  end

  describe 'proposal with direction: none' do
    let(:no_trade_output) do
      '{"symbol":"NIFTY","direction":"none","strike":null,"entry_price":null,' \
      '"stop_loss":null,"target":null,"quantity":null,"product":null,' \
      '"rationale":"No clear setup.","confidence":0.42,"risk_reward":null}'
    end

    before do
      mock_llm_sequence(market_output, options_output, no_trade_output, risk_output)
    end

    it 'returns nil proposal when direction is none' do
      result = described_class.run('Generate a NIFTY trade setup')
      expect(result[:proposal]).to be_nil
    end
  end
end
