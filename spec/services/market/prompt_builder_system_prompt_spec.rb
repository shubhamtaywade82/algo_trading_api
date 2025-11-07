# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Market::PromptBuilder do
  describe '.system_prompt' do
    it 'returns the options trader prompt for analysis requests' do
      prompt = described_class.system_prompt(:analysis)

      expect(prompt).to include('OptionsTrader-INDIA v1')
      expect(prompt).to include('OBJECTIVE')
    end

    it 'reuses the same prompt for options buying requests' do
      prompt = described_class.system_prompt(:options_buying)

      expect(prompt).to include('OptionsTrader-INDIA v1')
    end
  end
end
