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

    it 'falls back to unknown command message when pattern not matched' do
      expect(TelegramBot::ManualSignalTrigger).not_to receive(:call)

      described_class.new(chat_id:, command: '/unknown').call

      expect(TelegramNotifier).to have_received(:send_message).with('❓ Unknown command: /unknown', chat_id: chat_id)
    end
  end
end
