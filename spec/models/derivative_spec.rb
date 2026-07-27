# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Derivative do
  describe 'validations' do
    it 'accepts an option carrying a strike and a CE/PE type' do
      expect(build(:derivative)).to be_valid
    end

    it 'accepts a future, which has neither strike nor option type' do
      expect(build(:derivative, :future)).to be_valid
    end

    it 'rejects an option missing its strike' do
      derivative = build(:derivative, strike_price: nil)

      expect(derivative).not_to be_valid
      expect(derivative.errors[:strike_price]).to be_present
    end

    it 'rejects an option type the exchange does not issue' do
      expect(build(:derivative, option_type: 'XX')).not_to be_valid
    end

    it 'rejects a non-positive lot size' do
      derivative = build(:derivative, lot_size: 0)

      expect(derivative).not_to be_valid
      expect(derivative.errors[:lot_size]).to be_present
    end

    it 'rejects a negative strike' do
      derivative = build(:derivative, strike_price: -50)

      expect(derivative).not_to be_valid
      expect(derivative.errors[:strike_price]).to be_present
    end
  end

  # activerecord-import skips validations, so the import path is guarded by the
  # database alone. update_column throughout: bypassing the model is the point.
  # rubocop:disable Rails/SkipsModelValidations
  describe 'CHECK constraints' do
    let(:derivative) { create(:derivative) }

    it 'rejects a non-positive lot_size' do
      expect { derivative.update_column(:lot_size, 0) }
        .to raise_error(ActiveRecord::StatementInvalid, /chk_derivatives_lot_size_positive/)
    end

    it 'rejects a negative strike_price' do
      expect { derivative.update_column(:strike_price, -100) }
        .to raise_error(ActiveRecord::StatementInvalid, /chk_derivatives_strike_price_non_negative/)
    end

    it 'rejects an option_type outside CE/PE' do
      expect { derivative.update_column(:option_type, 'XX') }
        .to raise_error(ActiveRecord::StatementInvalid, /chk_derivatives_option_type_valid/)
    end

    it 'survives a bulk import of well-formed rows' do
      rows = [attributes_for(:derivative, security_id: '99001', symbol_name: 'NIFTY-BULK-CE').except(:instrument)]

      expect { described_class.import(rows, validate: false) }.to change(described_class, :count).by(1)
    end
  end
  # rubocop:enable Rails/SkipsModelValidations

  describe 'underlying link' do
    it 'stores a contract whose underlying is not in the instrument master' do
      expect(build(:derivative, instrument: nil)).to be_valid
    end

    it 'links to its underlying when one was matched' do
      contract = create(:derivative, :with_underlying)

      expect(contract.instrument.symbol_name).to eq('NIFTY')
    end
  end

  describe '.options_chain' do
    let(:expiry) { Time.zone.today + 7.days }

    before do
      create(:derivative, underlying_symbol: 'NIFTY', expiry_date: expiry, strike_price: 22_600, option_type: 'CE')
      create(:derivative, underlying_symbol: 'NIFTY', expiry_date: expiry, strike_price: 22_400, option_type: 'CE')
      create(:derivative, underlying_symbol: 'NIFTY', expiry_date: expiry, strike_price: 22_400, option_type: 'PE')
    end

    it 'returns both sides of the chain ordered by strike' do
      chain = described_class.options_chain('NIFTY', expiry)

      expect(chain.map { |d| [d.strike_price.to_i, d.option_type] })
        .to eq([[22_400, 'CE'], [22_400, 'PE'], [22_600, 'CE']])
    end

    it 'upcases the underlying so a lowercase caller still matches' do
      expect(described_class.options_chain('nifty', expiry).count).to eq(3)
    end

    it 'excludes a different expiry' do
      create(:derivative, underlying_symbol: 'NIFTY', expiry_date: expiry + 7.days, strike_price: 22_400,
                          option_type: 'CE')

      expect(described_class.options_chain('NIFTY', expiry).count).to eq(3)
    end

    it 'excludes retired contracts' do
      described_class.where(strike_price: 22_600).update_all(active: false) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.options_chain('NIFTY', expiry).count).to eq(2)
    end

    it 'excludes futures, which have no strike to sit on the chain' do
      create(:derivative, :future, underlying_symbol: 'NIFTY', expiry_date: expiry)

      expect(described_class.options_chain('NIFTY', expiry).count).to eq(3)
    end
  end

  describe '.for_tick' do
    it 'finds the contract the WebSocket addressed' do
      contract = create(:derivative, exchange: 'nse', segment: 'derivatives', security_id: '44444')

      expect(described_class.for_tick(exchange_segment: 'NSE_FNO', security_id: 44_444)).to eq(contract)
    end

    it 'does not cross segments' do
      create(:derivative, exchange: 'nse', segment: 'derivatives', security_id: '44444')

      expect(described_class.for_tick(exchange_segment: 'BSE_FNO', security_id: '44444')).to be_nil
    end
  end

  describe '.expiries_for' do
    it 'lists unexpired expiries nearest first, without duplicates' do
      near = Time.zone.today + 3.days
      far  = Time.zone.today + 10.days
      create(:derivative, underlying_symbol: 'NIFTY', expiry_date: far)
      create(:derivative, underlying_symbol: 'NIFTY', expiry_date: near)
      create(:derivative, underlying_symbol: 'NIFTY', expiry_date: near, option_type: 'PE')
      create(:derivative, :expired, underlying_symbol: 'NIFTY')

      expect(described_class.expiries_for('NIFTY')).to eq([near, far])
    end
  end

  describe '#exchange_segment' do
    it 'reads the column Postgres generates from exchange and segment' do
      contract = create(:derivative, exchange: 'bse', segment: 'derivatives')

      expect(contract.exchange_segment).to eq('BSE_FNO')
    end
  end
end
