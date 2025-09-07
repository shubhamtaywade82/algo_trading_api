# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PostbackLog, type: :model do
  describe 'basic functionality' do
    it 'can be created' do
      postback_log = build(:postback_log)
      expect(postback_log).to be_valid
    end

    it 'inherits from ApplicationRecord' do
      expect(PostbackLog.superclass).to eq(ApplicationRecord)
    end
  end

  describe 'factory' do
    it 'creates a valid postback log' do
      postback_log = create(:postback_log)
      expect(postback_log).to be_persisted
    end
  end
end
