# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Market::IndexWatchlist do
  def with_env(vars)
    stub_const('ENV', ENV.to_h.merge(vars).compact)
  end

  describe '.symbols' do
    it 'defaults to the three indices the app has processors and seeds for' do
      with_env('INDEX_WATCHLIST' => nil)

      expect(described_class.symbols).to eq(%w[NIFTY BANKNIFTY SENSEX])
    end

    it 'reads a comma separated list, upcasing and trimming' do
      with_env('INDEX_WATCHLIST' => ' nifty , FinNifty ')

      expect(described_class.symbols).to eq(%w[NIFTY FINNIFTY])
    end

    it 'de-duplicates so a repeated symbol is not scanned twice' do
      with_env('INDEX_WATCHLIST' => 'NIFTY,nifty,SENSEX')

      expect(described_class.symbols).to eq(%w[NIFTY SENSEX])
    end

    # An empty or whitespace-only value is a misconfiguration, not a request to
    # watch nothing — falling back keeps the scanner working.
    it 'falls back to the default when the list is blank' do
      with_env('INDEX_WATCHLIST' => ' , ')

      expect(described_class.symbols).to eq(%w[NIFTY BANKNIFTY SENSEX])
    end
  end

  describe '.exchange_for' do
    it 'routes the BSE indices to BSE and everything else to NSE' do
      expect(described_class.exchange_for('SENSEX')).to eq(:bse)
      expect(described_class.exchange_for('BANKEX')).to eq(:bse)
      expect(described_class.exchange_for('NIFTY')).to eq(:nse)
      expect(described_class.exchange_for('SOMETHING_NEW')).to eq(:nse)
    end
  end

  describe '.trading_enabled?' do
    it 'is off unless explicitly switched on' do
      with_env('INDEX_WATCHLIST_TRADING' => nil)

      expect(described_class).not_to be_trading_enabled
    end

    it 'is on for "true", case-insensitively' do
      with_env('INDEX_WATCHLIST_TRADING' => 'TRUE')

      expect(described_class).to be_trading_enabled
    end

    it 'is off for any other value' do
      with_env('INDEX_WATCHLIST_TRADING' => '1')

      expect(described_class).not_to be_trading_enabled
    end
  end

  describe '.min_level and .level_tradable?' do
    it 'defaults to high, so a medium signal does not trade' do
      with_env('INDEX_WATCHLIST_MIN_LEVEL' => nil)

      expect(described_class.min_level).to eq(:high)
      expect(described_class.level_tradable?(:high)).to be(true)
      expect(described_class.level_tradable?(:medium)).to be(false)
    end

    it 'lets medium through when configured' do
      with_env('INDEX_WATCHLIST_MIN_LEVEL' => 'medium')

      expect(described_class.level_tradable?(:medium)).to be(true)
      expect(described_class.level_tradable?(:high)).to be(true)
    end

    it 'ignores a nonsense value rather than trading on everything' do
      with_env('INDEX_WATCHLIST_MIN_LEVEL' => 'whatever')

      expect(described_class.min_level).to eq(:high)
    end

    # :none is what the detector returns below its medium threshold. Accepting
    # it as a floor would trade every non-zero score.
    it 'refuses :none as a floor' do
      with_env('INDEX_WATCHLIST_MIN_LEVEL' => 'none')

      expect(described_class.min_level).to eq(:high)
      expect(described_class.level_tradable?(:none)).to be(false)
    end
  end

  describe 'bounds' do
    it 'clamps the cooldown, the daily cap and the scan interval into sane ranges' do
      with_env(
        'INDEX_WATCHLIST_COOLDOWN_MINUTES' => '0',
        'INDEX_WATCHLIST_MAX_TRADES_PER_DAY' => '9999',
        'INDEX_WATCHLIST_SCAN_SECONDS' => '1'
      )

      expect(described_class.cooldown).to eq(1.minute)
      expect(described_class.max_trades_per_day).to eq(50)
      expect(described_class.scan_interval).to eq(30)
    end

    it 'uses the documented defaults when unset' do
      with_env(
        'INDEX_WATCHLIST_COOLDOWN_MINUTES' => nil,
        'INDEX_WATCHLIST_MAX_TRADES_PER_DAY' => nil,
        'INDEX_WATCHLIST_SCAN_SECONDS' => nil
      )

      expect(described_class.cooldown).to eq(30.minutes)
      expect(described_class.max_trades_per_day).to eq(3)
      expect(described_class.scan_interval).to eq(180)
    end
  end

  describe '.instruments' do
    it 'resolves index-segment instruments and skips symbols the scrip master lacks' do
      create(:instrument, :nifty)
      with_env('INDEX_WATCHLIST' => 'NIFTY,NOTLISTED')

      expect(described_class.instruments.map(&:underlying_symbol)).to eq(['NIFTY'])
    end

    # An equity row with the same symbol must not be mistaken for the index.
    it 'only looks in the index segment' do
      create(:instrument, underlying_symbol: 'NIFTY', segment: 'equity')
      with_env('INDEX_WATCHLIST' => 'NIFTY')

      expect(described_class.instrument_for('NIFTY')).to be_nil
    end
  end
end
