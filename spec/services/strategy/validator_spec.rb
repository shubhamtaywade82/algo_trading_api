# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strategy::Validator do
  let(:valid_proposal) do
    {
      symbol:       'NIFTY',
      direction:    'CE',
      strike:       24300,
      expiry:       (Date.today + 7).to_s,
      entry_price:  62.5,
      stop_loss:    42.0,
      target:       110.0,
      quantity:     75,
      product:      'INTRADAY',
      confidence:   0.75,
      risk_reward:  2.3,
      risk_approved: true
    }
  end

  describe '.valid?' do
    it 'returns true for a valid proposal' do
      expect(described_class.valid?(valid_proposal)).to be true
    end

    it 'returns false when a required field is missing' do
      expect(described_class.valid?(valid_proposal.except(:strike))).to be false
    end

    it 'returns false for direction "none"' do
      proposal = valid_proposal.merge(direction: 'none')
      expect(described_class.valid?(proposal)).to be false
    end

    it 'returns false when stop_loss >= entry_price' do
      proposal = valid_proposal.merge(stop_loss: 70.0)
      expect(described_class.valid?(proposal)).to be false
    end

    it 'returns false when target <= entry_price' do
      proposal = valid_proposal.merge(target: 50.0)
      expect(described_class.valid?(proposal)).to be false
    end

    it 'returns false when confidence is too low' do
      proposal = valid_proposal.merge(confidence: 0.45)
      expect(described_class.valid?(proposal)).to be false
    end

    it 'returns false when risk-reward is below minimum' do
      # entry=62.5, sl=55 (risk=7.5), target=72 (reward=9.5) → RR=1.27
      proposal = valid_proposal.merge(stop_loss: 55.0, target: 72.0)
      expect(described_class.valid?(proposal)).to be false
    end

    it 'returns false when risk agent rejected the trade' do
      proposal = valid_proposal.merge(risk_approved: false)
      expect(described_class.valid?(proposal)).to be false
    end

    it 'returns false when quantity is zero' do
      proposal = valid_proposal.merge(quantity: 0)
      expect(described_class.valid?(proposal)).to be false
    end

    it 'accepts string-keyed proposals' do
      string_keyed = valid_proposal.transform_keys(&:to_s)
      expect(described_class.valid?(string_keyed)).to be true
    end
  end

  describe '.validate' do
    it 'returns { valid: true, errors: [], warnings: [] } for a valid proposal' do
      result = described_class.validate(valid_proposal)
      expect(result[:valid]).to be true
      expect(result[:errors]).to be_empty
    end

    it 'returns descriptive errors for an invalid proposal' do
      bad_proposal = valid_proposal.merge(direction: 'XYZ', quantity: -1)
      result = described_class.validate(bad_proposal)

      expect(result[:valid]).to be false
      expect(result[:errors]).to include(a_string_matching(/direction/))
      expect(result[:errors]).to include(a_string_matching(/quantity/))
    end

    it 'warns about past expiry' do
      old_proposal = valid_proposal.merge(expiry: '2020-01-01')
      result = described_class.validate(old_proposal)

      expect(result[:warnings]).to include(a_string_matching(/past/i))
    end

    it 'warns about unusually high risk-reward' do
      high_rr = valid_proposal.merge(risk_reward: 8.0)
      result = described_class.validate(high_rr)

      expect(result[:warnings]).to include(a_string_matching(/risk_reward/i))
    end
  end
end
