require 'rails_helper'

RSpec.describe MarketAnalysisJob, type: :job do
  describe '#perform' do
    let(:chat_id) { '123456789' }
    let(:symbol) { 'RELIANCE' }
    let(:exchange) { :nse }

    before do
      allow(Market::AnalysisService).to receive(:call).and_return('Analysis result')
      allow(TelegramNotifier).to receive(:send_message)
    end

    it 'calls Market::AnalysisService with correct parameters' do
      described_class.perform_now(chat_id, symbol, exchange: exchange)

      expect(Market::AnalysisService).to have_received(:call).with(symbol, exchange: exchange, trade_type: nil)
    end

    it 'sends telegram notification when analysis is present' do
      described_class.perform_now(chat_id, symbol, exchange: exchange)

      expect(TelegramNotifier).to have_received(:send_message).with('Analysis result', chat_id: chat_id)
    end

    it 'does not send notification when analysis is empty' do
      allow(Market::AnalysisService).to receive(:call).and_return('')

      described_class.perform_now(chat_id, symbol, exchange: exchange)

      expect(TelegramNotifier).not_to have_received(:send_message)
    end

    it 'does not send notification when analysis is nil' do
      allow(Market::AnalysisService).to receive(:call).and_return(nil)

      described_class.perform_now(chat_id, symbol, exchange: exchange)

      expect(TelegramNotifier).not_to have_received(:send_message)
    end

    context 'when Market::AnalysisService raises an error' do
      let(:error_message) { 'Analysis failed' }

      before do
        allow(Market::AnalysisService).to receive(:call).and_raise(StandardError, error_message)
        allow(Rails.logger).to receive(:error)
      end

      it 'logs the error' do
        described_class.perform_now(chat_id, symbol, exchange: exchange)

        expect(Rails.logger).to have_received(:error).with(/MarketAnalysisJob.*#{error_message}/)
      end

      it 'sends error notification to telegram' do
        described_class.perform_now(chat_id, symbol, exchange: exchange)

        expect(TelegramNotifier).to have_received(:send_message).with(
          '🚨 Error running analysis. Please try again shortly.',
          chat_id: chat_id
        )
      end
    end
  end
end
