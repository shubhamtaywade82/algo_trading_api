# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Level, type: :model do
  describe 'associations' do
    it { should belong_to(:instrument) }
  end

  describe 'factory' do
    it 'creates a valid level' do
      level = build(:level)
      expect(level).to be_valid
    end

    it 'creates a level with required instrument association' do
      level = create(:level)
      expect(level.instrument).to be_present
    end
  end
end
