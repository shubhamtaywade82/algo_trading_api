# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TelegramBot::CommandHandler do
  let(:chat_id) { 'chat-1' }

  before do
    allow(TelegramNotifier).to receive(:send_message)
  end

  describe '#call' do
    it 'delegates nifty ce command to the manual trigger' do
      expect(TelegramBot::ManualSignalTrigger).to receive(:call).with(
        chat_id: chat_id,
        symbol: 'NIFTY',
        option: :ce,
        exchange: :nse
      )

      described_class.new(chat_id:, command: 'nifty ce').call
    end

    it 'delegates slash command variant to the manual trigger' do
      expect(TelegramBot::ManualSignalTrigger).to receive(:call).with(
        chat_id: chat_id,
        symbol: 'BANKNIFTY',
        option: :pe,
        exchange: :nse
      )

      described_class.new(chat_id:, command: '/banknifty_pe').call
    end

    it 'routes sensex commands to the BSE exchange' do
      expect(TelegramBot::ManualSignalTrigger).to receive(:call).with(
        chat_id: chat_id,
        symbol: 'SENSEX',
        option: :ce,
        exchange: :bse
      )

      described_class.new(chat_id:, command: 'sensex-ce').call
    end

    it 'handles /crypto_scan command' do
      allow(Crypto::Scanner).to receive(:call).and_return([])

      described_class.new(chat_id: chat_id, command: '/crypto_scan').call

      expect(TelegramNotifier).to have_received(:send_message).with(
        'ℹ️ Crypto scan complete: No qualifying setups found across configured symbols.',
        chat_id: chat_id
      )
    end

    it 'handles /crypto_analysis command with symbol argument' do
      dummy_analyzer = instance_double(Crypto::Analyzer)
      allow(Crypto::Analyzer).to receive(:new).with('BTCUSDT').and_return(dummy_analyzer)
      allow(dummy_analyzer).to receive(:reports).and_return({})
      allow(Crypto::SetupDetector).to receive(:call).and_return(nil)

      described_class.new(chat_id: chat_id, command: '/crypto_analysis BTCUSDT').call

      expect(TelegramNotifier).to have_received(:send_message).with(
        include('Crypto SMC Analysis – BTCUSDT'),
        chat_id: chat_id
      )
    end

    it 'falls back to unknown command message when pattern not matched' do
      expect(TelegramBot::ManualSignalTrigger).not_to receive(:call)

      described_class.new(chat_id:, command: '/unknown').call

      expect(TelegramNotifier).to have_received(:send_message).with('❓ Unknown command: /unknown', chat_id: chat_id)
    end
  end
end
