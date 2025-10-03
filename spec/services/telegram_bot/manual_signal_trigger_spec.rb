# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TelegramBot::ManualSignalTrigger do
  let(:chat_id) { 'chat-123' }
  let!(:instrument) { create(:instrument, :nifty) }
  let(:processor) { instance_double(AlertProcessors::Index, call: true) }

  before do
    allow_any_instance_of(Instrument).to receive(:quote_ltp).and_return(22_150.0)
    allow_any_instance_of(Instrument).to receive(:ltp).and_return(22_150.0)
    allow(TelegramNotifier).to receive(:send_chat_action)
    allow(TelegramNotifier).to receive(:send_message)
    allow(AlertProcessorFactory).to receive(:build).and_return(processor)
  end

  describe '.call' do
    it 'creates an alert and delegates to the alert processor' do
      expect do
        described_class.call(chat_id:, symbol: 'NIFTY', option: :ce, exchange: :nse)
      end.to change(Alert, :count).by(1)

      alert = Alert.last

      expect(alert.signal_type).to eq('long_entry')
      expect(alert.instrument_type).to eq('index')
      expect(AlertProcessorFactory).to have_received(:build).with(alert)
      expect(TelegramNotifier).to have_received(:send_chat_action).with(hash_including(chat_id: chat_id))
      expect(TelegramNotifier).to have_received(:send_message).with(/Manual NIFTY CE signal queued/, chat_id: chat_id)
    end

    it 'notifies when instrument lookup fails' do
      expect(TelegramNotifier).to receive(:send_message).with(/instrument not configured/i, chat_id: chat_id)

      result = described_class.call(chat_id:, symbol: 'SENSEX', option: :ce, exchange: :bse)

      expect(result).to be_nil
    end
  end
end
