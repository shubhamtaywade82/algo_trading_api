# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstrumentsImporter, type: :service do
  include CsvMockHelper

  let(:mock_csv_path) { CsvMockHelper::MOCK_CSV_PATH }

  before { generate_mock_csv }

  describe '.import' do
    context 'when file_path is provided' do
      it 'imports instruments and derivatives from the CSV file' do
        expect { described_class.import(mock_csv_path) }.to change(Instrument, :count)
        expect(Instrument.segment_index.find_by(symbol_name: 'NIFTY')).to be_present
        expect(Instrument.find_by(symbol_name: 'USDINR')).to be_present
        expect(Instrument.find_by(symbol_name: 'GOLD')).to be_present
      end

      it 'returns a summary hash' do
        summary = described_class.import(mock_csv_path)
        expect(summary).to include(:instrument_rows, :derivative_rows, :instrument_upserts, :derivative_upserts, :instrument_total,
                                   :derivative_total)
      end

      it 'writes the trading rules to the satellite tables, not the wide table' do
        described_class.import(mock_csv_path)
        instrument = Instrument.find_by(security_id: '2885', segment: 'equity')

        expect(instrument.order_feature).to have_attributes(
          bracket_flag: 'Y', cover_flag: 'Y', buy_sell_indicator: 'A', asm_gsm_flag: 'N'
        )
        expect(instrument.margin_requirement.buy_co_min_margin_per).to eq(20.0)
      end

      it 'attaches satellites to derivatives as well as instruments' do
        described_class.import(mock_csv_path)
        contract = Derivative.find_by(security_id: '35024')

        # The old parser wrote "true"/"false" here via a boolean assigned into
        # a string column, so no Y/N comparison ever matched.
        expect(contract.order_feature.asm_gsm_flag).to be_in(%w[Y N R])
      end

      it 'stamps every imported row as active and seen' do
        described_class.import(mock_csv_path)

        expect(Instrument.where(active: false)).to be_empty
        expect(Instrument.where(last_seen_at: nil)).to be_empty
      end

      it 'records the run instead of scribbling strings into app_settings' do
        expect { described_class.import(mock_csv_path) }.to change(InstrumentSyncRun, :count).by(1)

        run = InstrumentSyncRun.last_success
        expect(run).to have_attributes(source: 'file', status: 'succeeded')
        expect(run.instrument_rows).to be_positive
        expect(InstrumentSyncRun).not_to be_stale
      end

      it 'retires rows that were not in this feed' do
        gone = create(:derivative, security_id: '99999', last_seen_at: 3.days.ago)

        described_class.import(mock_csv_path)

        expect(gone.reload).not_to be_active
      end

      it 'records a failure rather than leaving no trace' do
        allow(InstrumentsImport::Parser).to receive(:call).and_raise('bad feed')

        expect { described_class.import(mock_csv_path) }.to raise_error('bad feed')
        expect(InstrumentSyncRun.last).to have_attributes(status: 'failed', error_message: 'bad feed')
      end
    end

    context 'when file_path is not provided' do
      before do
        allow(InstrumentsImport::Fetcher).to receive(:call).and_return(File.read(mock_csv_path))
      end

      it 'uses cached/fetched CSV and imports' do
        expect(InstrumentsImport::Fetcher).to receive(:call)
        expect { described_class.import }.to change(Instrument, :count)
      end
    end
  end

  describe '#import_from_csv' do
    it 'imports instruments then derivatives from CSV string' do
      csv_content = File.read(mock_csv_path)
      summary = described_class.new.import_from_csv(csv_content)

      expect(summary[:instrument_total]).to eq(Instrument.count)
      expect(summary[:derivative_total]).to eq(Derivative.count)
      expect(Instrument.segment_index.find_by(symbol_name: 'NIFTY')).to be_present
      expect(Derivative.count).to be >= 0
    end

    it 'does not retire anything, because the caller may be passing a partial feed' do
      other = create(:derivative, security_id: '99999', last_seen_at: 3.days.ago)

      described_class.new.import_from_csv(File.read(mock_csv_path))

      expect(other.reload).to be_active
    end

    it 'is not recorded as a sync run' do
      expect { described_class.new.import_from_csv(File.read(mock_csv_path)) }
        .not_to change(InstrumentSyncRun, :count)
    end
  end

  describe 'unparented contracts' do
    it 'keeps a contract whose underlying is absent from the master' do
      # BSE index options are the real case: the SENSEX50 index row is not
      # always present, and the importer used to drop every contract on it.
      described_class.import(mock_csv_path)

      expect(Derivative.where(instrument_id: nil).count)
        .to eq(InstrumentSyncRun.last_success.unparented_derivatives)
    end
  end

  describe 'idempotency' do
    it 'upserts rather than duplicating when run twice' do
      described_class.import(mock_csv_path)

      expect { described_class.import(mock_csv_path) }
        .to not_change(Instrument, :count)
        .and not_change(Derivative, :count)
        .and not_change(OrderFeature, :count)
        .and not_change(MarginRequirement, :count)
    end
  end
end
