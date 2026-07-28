# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaperAccount do
  def with_env(vars)
    stub_const('ENV', ENV.to_h.merge(vars).compact)
  end

  describe '.configured_capital' do
    it 'reads PAPER_CAPITAL' do
      with_env('PAPER_CAPITAL' => '100000')

      expect(described_class.configured_capital).to eq(100_000)
    end

    it 'accepts the separators a rupee figure gets typed with' do
      with_env('PAPER_CAPITAL' => '1_00_000')
      expect(described_class.configured_capital).to eq(100_000)

      with_env('PAPER_CAPITAL' => '2,50,000')
      expect(described_class.configured_capital).to eq(250_000)
    end

    it 'falls back to the default when unset' do
      with_env('PAPER_CAPITAL' => nil)

      expect(described_class.configured_capital).to eq(described_class::DEFAULT_CAPITAL)
    end

    # A typo must not create a book with zero capital, where every order is
    # rejected for margin and the run looks like a strategy failure.
    it 'falls back rather than creating a zero-capital book' do
      with_env('PAPER_CAPITAL' => 'not a number')
      expect(described_class.configured_capital).to eq(described_class::DEFAULT_CAPITAL)

      with_env('PAPER_CAPITAL' => '0')
      expect(described_class.configured_capital).to eq(described_class::DEFAULT_CAPITAL)

      with_env('PAPER_CAPITAL' => '-5000')
      expect(described_class.configured_capital).to eq(described_class::DEFAULT_CAPITAL)
    end
  end

  describe '.current' do
    it 'creates the book at the configured capital' do
      with_env('PAPER_CAPITAL' => '100000')

      account = described_class.current

      expect(account.initial_capital).to eq(100_000)
      expect(account.available_balance).to eq(100_000)
    end

    # Re-capitalising a running book on every boot would rewrite the
    # denominator of every P&L figure it has already produced.
    it 'leaves an existing book alone when the env changes' do
      with_env('PAPER_CAPITAL' => '100000')
      described_class.current

      with_env('PAPER_CAPITAL' => '500000')

      expect(described_class.current.initial_capital).to eq(100_000)
      expect(described_class.count).to eq(1)
    end
  end

  describe '.recapitalize!' do
    it 'sets the capital and resets the book to it' do
      with_env('PAPER_CAPITAL' => '1000000')
      account = described_class.current
      account.update!(available_balance: 250, realized_pnl: -1_500, total_charges: 90, blocked_margin: 400)

      described_class.recapitalize!(100_000)

      expect(account.reload).to have_attributes(
        initial_capital: 100_000,
        available_balance: 100_000,
        blocked_margin: 0,
        realized_pnl: 0,
        total_charges: 0
      )
      expect(account.reset_at).to be_present
    end

    it 'defaults to PAPER_CAPITAL when given no argument' do
      described_class.current
      with_env('PAPER_CAPITAL' => '100000')

      expect(described_class.recapitalize!.initial_capital).to eq(100_000)
    end

    it 'refuses a non-positive figure' do
      described_class.current

      expect { described_class.recapitalize!(0) }.to raise_error(ArgumentError)
    end
  end
end
