# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Paper::Broker do
  describe '.enabled?' do
    around do |example|
      orig_paper_trading = ENV.fetch('PAPER_TRADING', nil)
      orig_paper_mode = ENV.fetch('PAPER_MODE', nil)
      example.run
    ensure
      ENV['PAPER_TRADING'] = orig_paper_trading
      ENV['PAPER_MODE'] = orig_paper_mode
    end

    it 'returns true when PAPER_TRADING is "true"' do
      ENV['PAPER_TRADING'] = 'true'
      ENV['PAPER_MODE'] = nil
      expect(described_class.enabled?).to be true
    end

    it 'returns true when PAPER_MODE is "1"' do
      ENV['PAPER_TRADING'] = nil
      ENV['PAPER_MODE'] = '1'
      expect(described_class.enabled?).to be true
    end

    it 'returns false when both flags are unset' do
      ENV['PAPER_TRADING'] = nil
      ENV['PAPER_MODE'] = nil
      expect(described_class.enabled?).to be false
    end
  end
end
