# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstrumentsImport::Parser, type: :service do
  # The detailed scrip master's column order, verbatim.
  def headers
    %w[
      EXCH_ID SEGMENT SECURITY_ID ISIN INSTRUMENT UNDERLYING_SECURITY_ID UNDERLYING_SYMBOL
      SYMBOL_NAME DISPLAY_NAME INSTRUMENT_TYPE SERIES LOT_SIZE SM_EXPIRY_DATE STRIKE_PRICE
      OPTION_TYPE TICK_SIZE EXPIRY_FLAG BRACKET_FLAG COVER_FLAG ASM_GSM_FLAG ASM_GSM_CATEGORY
      BUY_SELL_INDICATOR BUY_CO_MIN_MARGIN_PER SELL_CO_MIN_MARGIN_PER BUY_CO_SL_RANGE_MAX_PERC
      SELL_CO_SL_RANGE_MAX_PERC BUY_CO_SL_RANGE_MIN_PERC SELL_CO_SL_RANGE_MIN_PERC
      BUY_BO_MIN_MARGIN_PER SELL_BO_MIN_MARGIN_PER BUY_BO_SL_RANGE_MAX_PERC
      SELL_BO_SL_RANGE_MAX_PERC BUY_BO_SL_RANGE_MIN_PERC SELL_BO_SL_MIN_RANGE
      BUY_BO_PROFIT_RANGE_MAX_PERC SELL_BO_PROFIT_RANGE_MAX_PERC BUY_BO_PROFIT_RANGE_MIN_PERC
      SELL_BO_PROFIT_RANGE_MIN_PERC MTF_LEVERAGE
    ]
  end

  def csv_for(**overrides)
    defaults = {
      'EXCH_ID' => 'NSE', 'SEGMENT' => 'E', 'SECURITY_ID' => '2885', 'ISIN' => 'INE002A01018',
      'INSTRUMENT' => 'EQUITY', 'UNDERLYING_SYMBOL' => 'RELIANCE',
      'SYMBOL_NAME' => 'RELIANCE INDUSTRIES LTD', 'DISPLAY_NAME' => 'Reliance',
      'INSTRUMENT_TYPE' => 'ES', 'SERIES' => 'EQ', 'LOT_SIZE' => '1', 'TICK_SIZE' => '0.05',
      'BRACKET_FLAG' => 'Y', 'COVER_FLAG' => 'Y', 'ASM_GSM_FLAG' => 'N',
      'ASM_GSM_CATEGORY' => 'NA', 'BUY_SELL_INDICATOR' => 'A',
      'BUY_CO_MIN_MARGIN_PER' => '20.00', 'MTF_LEVERAGE' => '3.773585'
    }.merge(overrides)

    CSV.generate do |csv|
      csv << headers
      csv << headers.map { |h| defaults[h] }
    end
  end

  it 'routes a cash-segment row to instruments' do
    result = described_class.call(csv_for)

    expect(result[:instruments].size).to eq(1)
    expect(result[:derivatives]).to be_empty
    expect(result[:instruments].first).to include(security_id: '2885', segment: 'E', active: true)
  end

  it 'routes a derivatives-segment row to derivatives' do
    result = described_class.call(
      csv_for('SEGMENT' => 'D', 'INSTRUMENT' => 'OPTIDX', 'SECURITY_ID' => '35024',
              'SYMBOL_NAME' => 'NIFTY-Feb2025-29200-CE', 'UNDERLYING_SYMBOL' => 'NIFTY',
              'SM_EXPIRY_DATE' => '2025-02-27', 'STRIKE_PRICE' => '29200.00000',
              'OPTION_TYPE' => 'CE', 'EXPIRY_FLAG' => 'W')
    )

    expect(result[:instruments]).to be_empty
    expect(result[:derivatives].first).to include(
      security_id: '35024', option_type: 'CE', expiry_date: Date.new(2025, 2, 27)
    )
  end

  # MCX futures carry OPTION_TYPE "XX". Stored verbatim they match neither
  # Derivative#option? nor the futures scope, and they violate the CE/PE check
  # constraint, which aborts the whole import.
  it 'nils out the MCX futures sentinel option type' do
    result = described_class.call(
      csv_for('EXCH_ID' => 'MCX', 'SEGMENT' => 'M', 'INSTRUMENT' => 'FUTCOM',
              'SECURITY_ID' => '428750', 'SYMBOL_NAME' => 'GOLD',
              'SM_EXPIRY_DATE' => '2025-02-05', 'OPTION_TYPE' => 'XX')
    )

    expect(result[:instruments].first).to include(option_type: nil)
  end

  it 'keeps a real option type' do
    result = described_class.call(csv_for('SEGMENT' => 'D', 'OPTION_TYPE' => 'pe'))

    expect(result[:derivatives].first).to include(option_type: 'PE')
  end

  it 'skips exchanges this app does not trade' do
    expect(described_class.call(csv_for('EXCH_ID' => 'XYZ'))[:instruments]).to be_empty
  end

  describe 'trading rules' do
    it 'splits the flags onto order_features rather than the wide table' do
      result = described_class.call(csv_for)

      expect(result[:order_features].first).to include(
        bracket_flag: 'Y', cover_flag: 'Y', buy_sell_indicator: 'A',
        asm_gsm_flag: 'N', asm_gsm_category: 'NA', mtf_leverage: 3.773585,
        owner_type: 'Instrument'
      )
      expect(result[:instruments].first.keys).not_to include(:bracket_flag, :asm_gsm_flag, :mtf_leverage)
    end

    it 'keeps the exchange Y/N for a derivative instead of coercing it to a boolean' do
      result = described_class.call(
        csv_for('SEGMENT' => 'D', 'INSTRUMENT' => 'OPTIDX', 'ASM_GSM_FLAG' => 'Y',
                'SM_EXPIRY_DATE' => '2025-02-27', 'OPTION_TYPE' => 'CE', 'STRIKE_PRICE' => '100')
      )

      # The previous parser assigned `row['ASM_GSM_FLAG'] == 'Y'` — a boolean —
      # into a string column, which stored "true"/"false".
      expect(result[:order_features].first).to include(asm_gsm_flag: 'Y', owner_type: 'Derivative')
    end

    it 'splits the CO/BO percentages onto margin_requirements' do
      result = described_class.call(csv_for)

      expect(result[:margin_requirements].first).to include(
        buy_co_min_margin_per: 20.0, owner_type: 'Instrument'
      )
    end

    it 'emits no satellite rows when the master carries no rules' do
      blank = headers.index_with { '' }.merge(
        'EXCH_ID' => 'NSE', 'SEGMENT' => 'E', 'SECURITY_ID' => '1',
        'SYMBOL_NAME' => 'X', 'INSTRUMENT' => 'EQUITY'
      )
      csv = CSV.generate do |out|
        out << headers
        out << headers.map { |h| blank[h] }
      end

      result = described_class.call(csv)

      expect(result[:order_features]).to be_empty
      expect(result[:margin_requirements]).to be_empty
    end

    it 'keys satellites to the owner natural key so they can be linked after upsert' do
      result = described_class.call(csv_for)

      expect(result[:order_features].first[:owner_key])
        .to eq(['2885', 'RELIANCE INDUSTRIES LTD', 'NSE', 'E'])
    end
  end

  it 'never emits the generated exchange_segment column, which Postgres refuses writes to' do
    result = described_class.call(csv_for)

    expect(result[:instruments].first.keys).not_to include(:exchange_segment)
  end
end
