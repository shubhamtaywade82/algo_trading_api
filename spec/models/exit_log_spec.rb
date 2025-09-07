# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExitLog, type: :model do
  describe 'basic functionality' do
    it 'can be created' do
      exit_log = build(:exit_log)
      expect(exit_log).to be_valid
    end

    it 'inherits from ApplicationRecord' do
      expect(ExitLog.superclass).to eq(ApplicationRecord)
    end
  end

  describe 'factory' do
    it 'creates a valid exit log' do
      exit_log = create(:exit_log)
      expect(exit_log).to be_persisted
    end
  end
end
