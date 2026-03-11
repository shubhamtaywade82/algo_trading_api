# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DhanAccessToken do
  describe '.active' do
    it 'returns the most recent token that has not expired' do
      described_class.create!(access_token: 'old', expires_at: 1.hour.ago)
      current = described_class.create!(access_token: 'current', expires_at: 1.day.from_now)

      expect(described_class.active).to eq(current)
    end

    it 'returns the most recently created when multiple are non-expired (Dhan invalidates older)' do
      older = described_class.create!(access_token: 'older_token', expires_at: 2.hours.from_now)
      newer = described_class.create!(access_token: 'newer_token', expires_at: 1.hour.from_now)

      expect(described_class.active.access_token).to eq('newer_token')
      expect(described_class.current_record.access_token).to eq('newer_token')
    end

    it 'returns nil when all tokens are expired', :no_dhan_token do
      described_class.create!(access_token: 'x', expires_at: 1.hour.ago)

      expect(described_class.active).to be_nil
    end
  end

  describe '.valid?' do
    it 'returns true when an active token exists' do
      described_class.create!(access_token: 't', expires_at: 1.day.from_now)

      expect(described_class).to be_valid
    end

    it 'returns false when no active token exists', :no_dhan_token do
      described_class.create!(access_token: 't', expires_at: 1.hour.ago)

      expect(described_class).not_to be_valid
    end
  end
end
