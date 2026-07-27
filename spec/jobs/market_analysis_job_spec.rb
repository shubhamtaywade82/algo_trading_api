require 'rails_helper'

RSpec.describe MarketAnalysisJob do
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

      expect(Market::AnalysisService).to have_received(:call).with(symbol, hash_including(exchange: exchange))
    end

    it 'sends telegram notification when analysis is present' do
      described_class.perform_now(chat_id, symbol, exchange: exchange)

      expect(TelegramNotifier).to have_received(:send_message).with('Analysis result', chat_id: chat_id)
    end

    # Market::AnalysisService returns nil for three different reasons, and the
    # one that happens on a freshly deployed database — an instrument master
    # that was never imported — used to be reported as "check data
    # availability", which names nothing the operator can act on.
    context 'when the analysis produces nothing' do
      before { allow(Market::AnalysisService).to receive(:call).and_return(nil) }

      it 'says the instrument master is empty when nothing has been imported' do
        described_class.perform_now(chat_id, symbol, exchange: exchange)

        expect(TelegramNotifier).to have_received(:send_message).with(
          /instrument master is empty/,
          hash_including(chat_id: chat_id)
        )
      end

      it 'names the import to run when the master is empty' do
        described_class.perform_now(chat_id, symbol, exchange: exchange)

        expect(TelegramNotifier).to have_received(:send_message).with(
          /instruments:import/,
          hash_including(chat_id: chat_id)
        )
      end

      it 'says the symbol is missing when the master is populated without it' do
        create(:instrument, :nifty)

        described_class.perform_now(chat_id, 'NOTASYMBOL', exchange: exchange)

        expect(TelegramNotifier).to have_received(:send_message).with(
          /NOTASYMBOL is not in the instrument master for NSE/,
          hash_including(chat_id: chat_id)
        )
      end

      it 'falls back to "returned no result" when the symbol does resolve' do
        create(:instrument, :nifty)

        described_class.perform_now(chat_id, 'NIFTY', exchange: exchange)

        expect(TelegramNotifier).to have_received(:send_message).with(
          /returned no result/,
          hash_including(chat_id: chat_id)
        )
      end

      it 'treats a blank answer the same as a nil one' do
        allow(Market::AnalysisService).to receive(:call).and_return('')

        described_class.perform_now(chat_id, symbol, exchange: exchange)

        expect(TelegramNotifier).to have_received(:send_message).with(
          /instrument master is empty/,
          hash_including(chat_id: chat_id)
        )
      end
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
          "🚨 Error running analysis – #{error_message}",
          chat_id: chat_id
        )
      end

      context 'when error is Faraday::ConnectionFailed' do
        before do
          allow(Market::AnalysisService).to receive(:call).and_raise(Faraday::ConnectionFailed, 'end of file reached')
        end

        it 'sends connection-unavailable message' do
          described_class.perform_now(chat_id, symbol, exchange: exchange)

          expect(TelegramNotifier).to have_received(:send_message).with(
            /Analysis service unavailable \(connection error\)/,
            hash_including(chat_id: chat_id)
          )
        end
      end

      context 'when error is Dhan authentication related' do
        before do
          allow(Market::AnalysisService).to receive(:call).and_raise(DhanHQ::InvalidAuthenticationError, 'Invalid token')
        end

        it 'sends Dhan session message' do
          described_class.perform_now(chat_id, symbol, exchange: exchange)

          expect(TelegramNotifier).to have_received(:send_message).with(
            /Dhan session or data access issue/,
            hash_including(chat_id: chat_id)
          )
        end
      end
    end
  end
end
