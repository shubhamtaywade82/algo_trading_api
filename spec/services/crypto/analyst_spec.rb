# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crypto::Analyst do
  subject(:plan) { described_class.new(setup, router: router).call }

  let(:router) { class_double(Openai::ChatRouter, ask!: 'ENTRY: limit into the block.') }

  let(:poi) do
    Crypto::Smc::Zone.new(kind: :order_block, direction: :bullish, top: 151.2, bottom: 149.8,
                          index: 40, time: Time.current)
  end

  let(:setup) do
    Crypto::Setup.new(
      symbol: 'SOLUSDT', direction: :long, score: 78.5, entry: 152.345, stop: 148.9,
      targets: [162.5, 171.0], risk: 3.445, risk_reward: 2.95,
      confluences: [
        { key: :daily_alignment, weight: 15, label: '1d structure bullish' },
        { key: :m5_trigger, weight: 15, label: '5m BOS through 151.900' }
      ],
      poi: poi,
      context: { bias: { '1d' => :bullish, '4h' => :bullish, '5m' => :bullish }, range_zone: :discount }
    )
  end

  describe 'the prompt' do
    before { plan }

    it 'states the fixed levels the model must not change' do
      expect(router).to have_received(:ask!).with(
        a_string_including('152.345', '148.900', '162.500', 'do not alter'),
        system: a_string_including('Never change'), model: nil
      )
    end

    it 'carries the multi-timeframe context and the point of interest' do
      expect(router).to have_received(:ask!).with(
        a_string_including('1d bullish', 'discount', 'order block'), any_args
      )
    end

    it 'names the confluences that fired' do
      expect(router).to have_received(:ask!).with(a_string_including('5m BOS through 151.900'), any_args)
    end

    it 'names the confluences that did not, so the caveat can be specific' do
      expect(router).to have_received(:ask!).with(a_string_including('Did not fire:', 'm15 sweep'), any_args)
    end
  end

  describe 'the response' do
    it 'returns the plan text' do
      expect(plan).to eq('ENTRY: limit into the block.')
    end

    it 'strips reasoning blocks the cloud models emit' do
      allow(router).to receive(:ask!).and_return("<think>hmm, maybe</think>\nENTRY: market on the trigger.")

      expect(plan).to eq('ENTRY: market on the trigger.')
    end

    it 'strips markdown so the plain-text message needs no escaping' do
      allow(router).to receive(:ask!).and_return("```\n**ENTRY:** limit at the _low_\n```")

      expect(plan).to eq('ENTRY: limit at the low')
    end

    it 'truncates a runaway answer' do
      allow(router).to receive(:ask!).and_return("#{'word ' * 1000}end")

      expect(plan.length).to be <= described_class::MAX_CHARS + 1
      expect(plan).to end_with('…')
    end
  end

  describe 'when it cannot answer' do
    it 'returns nil rather than raising, so the alert still sends' do
      allow(router).to receive(:ask!).and_raise(StandardError, 'ollama down')

      expect(plan).to be_nil
    end

    it 'stays out of the way entirely when disabled' do
      allow(Crypto::Config).to receive(:llm_enabled?).and_return(false)

      expect(plan).to be_nil
      expect(router).not_to have_received(:ask!)
    end
  end
end
