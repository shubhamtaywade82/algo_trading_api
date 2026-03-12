# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'AI::Tools — Agents::Tool subclasses' do
  describe AI::Tools::DhanCandleTool do
    subject(:tool) { described_class.new }

    it 'subclasses Agents::Tool' do
      expect(tool).to be_a(Agents::Tool)
    end

    it 'has a description set' do
      expect(described_class.description).to be_present
    end

    it 'declares required params (symbol, interval)' do
      param_names = described_class.params.map { |p| p[:name].to_s }
      expect(param_names).to include('symbol', 'interval')
    end
  end

  describe AI::Tools::OptionChainTool do
    it 'subclasses Agents::Tool' do
      expect(described_class.new).to be_a(Agents::Tool)
    end

    it 'declares :symbol as a required param' do
      required = described_class.params.select { |p| p[:required] }.map { |p| p[:name].to_s }
      expect(required).to include('symbol')
    end
  end

  describe AI::Tools::MarketSentimentTool do
    it 'subclasses Agents::Tool and declares :symbol' do
      param_names = described_class.params.map { |p| p[:name].to_s }
      expect(param_names).to include('symbol')
    end
  end

  describe AI::Tools::PositionsTool do
    it 'subclasses Agents::Tool' do
      expect(described_class.new).to be_a(Agents::Tool)
    end
  end

  describe AI::Tools::TradeLogTool do
    it 'subclasses Agents::Tool' do
      expect(described_class.new).to be_a(Agents::Tool)
    end
  end

  describe AI::Tools::BacktestTool do
    it 'declares symbol and strategy as required params' do
      required = described_class.params.select { |p| p[:required] }.map { |p| p[:name].to_s }
      expect(required).to include('symbol', 'strategy')
    end
  end

  describe AI::Tools::FundsTool do
    it 'subclasses Agents::Tool and needs no params' do
      expect(described_class.params).to be_blank
    end
  end
end
