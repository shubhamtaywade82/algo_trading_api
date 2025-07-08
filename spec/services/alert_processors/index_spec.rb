# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlertProcessors::Index, type: :service do
  subject(:processor) { described_class.new(alert) }

  let(:instrument) do
    create(
      :instrument,
      segment: 'index',
      exchange: 'NSE',
      security_id: '13',
      underlying_symbol: 'NIFTY',
      instrument: 'INDEX'
    )
  end

  let(:alert) do
    create(
      :alert,
      instrument_type: 'index',
      action: 'buy',
      signal_type: 'long_entry',
      strategy_type: 'intraday',
      ticker: 'NIFTY',
      exchange: 'NSE',
      time: Time.zone.now.iso8601,
      instrument: instrument
    )
  end

  let(:expiry_date) { Date.parse('2024-07-25') }
  let(:option_chain_data) do
    {
      last_price: 22_150.0,
      oc: {
        '22000.000000' => {
          'ce' => {
            'last_price' => 100.0,
            'implied_volatility' => 30.0,
            'oi' => 100_000,
            'greeks' => { 'delta' => 0.45 }
          },
          'pe' => {
            'last_price' => 80.0,
            'implied_volatility' => 28.0,
            'oi' => 90_000,
            'greeks' => { 'delta' => -0.40 }
          }
        }
      }
    }
  end

  let(:selected_strike) do
    {
      strike_price: 22_000,
      last_price: 100.0,
      iv: 30.0,
      oi: 100_000,
      greeks: { delta: 0.45 }
    }
  end

  let(:analyzer_result) do
    {
      proceed: true,
      trend: 'bullish',
      signal_type: :ce,
      selected: selected_strike,
      ranked: [selected_strike]
    }
  end

  let(:derivative) do
    create(
      :derivative,
      instrument: instrument,
      instrument_type: 'OPTIDX',
      symbol_name: 'OPTNIFTY22000CE',
      security_id: 'OPTNIFTY22000CE',
      expiry_date: expiry_date,
      strike_price: 22_000,
      exchange: 'NSE',
      segment: 'derivatives',
      option_type: 'CE',
      lot_size: 75
    )
  end

  before do
    allow(processor).to receive(:available_balance).and_return(100_000.0)
    allow(processor).to receive(:dhan_positions).and_return([])

    analyzer_double = instance_double('Option::ChainAnalyzer', analyze: analyzer_result)
    allow(Option::ChainAnalyzer).to receive(:new).and_return(analyzer_double)

    allow(processor).to receive(:fetch_derivative).and_return(derivative)
    allow(processor).to receive(:place_order!).and_return(true)
    allow(processor).to receive(:notify)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:warn)
  end

  describe '#call' do
    context 'when processing is successful' do
      it 'places an order and updates alert status to processed', vcr: { cassette_name: 'dhan/option_expiry_list' } do
        expect { processor.call }.to change { alert.reload.status }
          .from('pending').to('processed')
      end
    end

    context 'when analysis returns no viable strike' do
      before do
        allow(instrument).to receive(:expiry_list).and_return([expiry_date])
        allow(instrument).to receive(:fetch_option_chain).and_return(option_chain_data)

        analyzer_double = instance_double(
          Option::ChainAnalyzer,
          analyze: { proceed: false, reason: 'no viable strike' }
        )
        allow(Option::ChainAnalyzer).to receive(:new).and_return(analyzer_double)
      end

      it 'skips processing and updates alert as skipped', vcr: { cassette_name: 'dhan/option_expiry_list' } do
        expect { processor.call }.to change { alert.reload.status }
          .from('pending').to('processed')

        expect(alert.reload.error_message).to eq('no viable strike')
      end
    end

    context 'when a StandardError occurs' do
      before do
        allow(processor).to receive(:place_order!).and_raise('no_affordable_strike')
      end

      it 'updates alert as failed and logs error', vcr: { cassette_name: 'dhan/option_expiry_list' } do
        expect do
          processor.call
        end.not_to raise_error

        alert.reload
        expect(alert.status).to eq('processed')
        expect(alert.error_message).to eq('no_affordable_strike')
      end
    end

    context 'when dry-run mode is active' do
      before do
        stub_const('ENV', ENV.to_hash.merge('PLACE_ORDER' => 'false'))
        allow(processor).to receive(:dry_run).and_call_original
      end

      it 'performs dry-run instead of placing real order' do
        expect(processor).to receive(:dry_run).once

        processor.call

        expect(alert.reload.status).to eq('skipped')
        expect(alert.error_message).to eq('PLACE_ORDER disabled')
      end
    end

    context 'when there is no affordable strike' do
      before do
        # simulate that selected strike is too expensive
        allow(processor).to receive(:strike_affordable?).and_return(false)
        allow(processor).to receive(:pick_affordable_strike).and_return(nil)
      end

      it 'skips processing and logs a message' do
        expect { processor.call }.to change { alert.reload.status }
          .from('pending').to('skipped')

        expect(alert.reload.error_message).to eq('no_affordable_strike')
      end
    end

    context 'when exit signal is received' do
      let(:alert) do
        create(
          :alert,
          instrument_type: 'index',
          action: 'sell',
          signal_type: 'long_exit',
          strategy_type: 'intraday',
          ticker: 'NIFTY',
          exchange: 'NSE',
          time: Time.zone.now.iso8601,
          instrument: instrument
        )
      end

      it 'calls exit_position! and marks alert as processed' do
        allow(processor).to receive(:exit_position!).and_return(false)

        processor.call

        expect(processor).to have_received(:exit_position!).with(:ce)
        expect(alert.reload.status).to eq('skipped')
      end
    end
  end
end
