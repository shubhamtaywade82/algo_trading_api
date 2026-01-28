# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Capital-Aware Position Sizing', type: :service do
  # Test the capital-aware sizing logic across all alert processors

  describe AlertProcessors::Index do
    let(:instrument) { create(:instrument, underlying_symbol: 'NIFTY') }
    let(:alert) { create(:alert, instrument: instrument, signal_type: 'long_entry') }
    let(:processor) { described_class.new(alert) }

    before do
      allow(processor).to receive_messages(available_balance: balance, instrument: instrument, current_atr_pct: nil) # Mock ATR to avoid DB issues
    end

    describe '#deployment_policy' do
      context 'with ₹50K balance' do
        let(:balance) { 50_000 }

        it 'returns correct policy for small account' do
          policy = processor.send(:deployment_policy, balance)
          expect(policy[:alloc_pct]).to eq(0.30)
          expect(policy[:risk_per_trade_pct]).to eq(0.050)
          expect(policy[:daily_max_loss_pct]).to eq(0.050)
        end
      end

      context 'with ₹1L balance' do
        let(:balance) { 100_000 }

        it 'returns correct policy for medium account' do
          policy = processor.send(:deployment_policy, balance)
          expect(policy[:alloc_pct]).to eq(0.25)
          expect(policy[:risk_per_trade_pct]).to eq(0.035)
          expect(policy[:daily_max_loss_pct]).to eq(0.060)
        end
      end

      context 'with ₹2L balance' do
        let(:balance) { 200_000 }

        it 'returns correct policy for large account' do
          policy = processor.send(:deployment_policy, balance)
          expect(policy[:alloc_pct]).to eq(0.20)
          expect(policy[:risk_per_trade_pct]).to eq(0.030)
          expect(policy[:daily_max_loss_pct]).to eq(0.060)
        end
      end

      context 'with ₹5L balance' do
        let(:balance) { 500_000 }

        it 'returns correct policy for very large account' do
          policy = processor.send(:deployment_policy, balance)
          expect(policy[:alloc_pct]).to eq(0.20)
          expect(policy[:risk_per_trade_pct]).to eq(0.025)
          expect(policy[:daily_max_loss_pct]).to eq(0.050)
        end
      end
    end

    describe '#calculate_quantity' do
      let(:strike) { { strike_price: 18_000, last_price: 150.0 } }
      let(:lot_size) { 75 }

      context 'with ₹50K balance and ₹15K/lot option' do
        let(:balance) { 50_000 }

        it 'calculates correct quantity based on allocation and risk constraints' do
          # Allocation: 50K * 0.30 = 15K, 15K / 15K = 1 lot
          # Risk: 50K * 0.05 = 2.5K, 15K * 0.15 = 2.25K risk/lot, 2.5K / 2.25K = 1 lot
          # Affordability: 50K / 15K = 3 lots
          # Min of [1, 1, 3] = 1 lot

          quantity = processor.send(:calculate_quantity, strike, lot_size)
          expect(quantity).to eq(75) # 1 lot * 75 lot_size
        end
      end

      context 'with ₹1L balance and ₹15K/lot option' do
        let(:balance) { 100_000 }

        it 'calculates correct quantity for medium account' do
          # Allocation: 1L * 0.25 = 25K, 25K / 15K = 1 lot
          # Risk: 1L * 0.035 = 3.5K, 15K * 0.18 = 2.7K risk/lot, 3.5K / 2.7K = 1 lot
          # Affordability: 1L / 15K = 6 lots
          # Min of [1, 1, 6] = 1 lot

          quantity = processor.send(:calculate_quantity, strike, lot_size)
          expect(quantity).to eq(75) # 1 lot * 75 lot_size
        end
      end

      context 'with ₹2L balance and ₹15K/lot option' do
        let(:balance) { 200_000 }

        it 'calculates correct quantity for large account' do
          # Allocation: 2L * 0.20 = 40K, 40K / 15K = 2 lots
          # Risk: 2L * 0.030 = 6K, 15K * 0.18 = 2.7K risk/lot, 6K / 2.7K = 2 lots
          # Affordability: 2L / 15K = 13 lots
          # Min of [2, 2, 13] = 2 lots

          quantity = processor.send(:calculate_quantity, strike, lot_size)
          expect(quantity).to eq(150) # 2 lots * 75 lot_size
        end
      end

      context 'with insufficient balance' do
        let(:balance) { 10_000 }
        let(:strike) { { strike_price: 18_000, last_price: 200.0 } } # ₹15K/lot

        it 'returns 0 when cannot afford even one lot' do
          quantity = processor.send(:calculate_quantity, strike, lot_size)
          expect(quantity).to eq(0)
        end
      end

      context 'with zero lot size' do
        let(:balance) { 100_000 }
        let(:lot_size) { 0 }

        it 'returns 0 and logs error' do
          expect(processor).to receive(:log).with(:error, /Invalid sizing inputs/)
          quantity = processor.send(:calculate_quantity, strike, lot_size)
          expect(quantity).to eq(0)
        end
      end
    end

    describe '#effective_sl_pct' do
      let(:balance) { 100_000 }

      context 'with ATR-adaptive stop loss' do
        before do
          allow(processor).to receive(:rrules_for).and_return({
                                                                stop_loss: 123.0, # 18% below 150
                                                                target: 195.0,
                                                                trail_jump: 9.0
                                                              })
        end

        it 'calculates SL% from ATR-based rules' do
          sl_pct = processor.send(:effective_sl_pct, 150.0)
          expect(sl_pct).to be_within(0.001).of(0.18) # (150 - 123) / 150
        end
      end

      context 'without ATR data' do
        before do
          allow(processor).to receive(:rrules_for).and_return(nil)
        end

        it 'falls back to default SL%' do
          sl_pct = processor.send(:effective_sl_pct, 150.0)
          expect(sl_pct).to eq(0.18) # DEFAULT_STOP_LOSS_PCT
        end
      end
    end

    describe '#daily_loss_guard_ok?' do
      let(:balance) { 100_000 }

      before do
        allow(processor).to receive_messages(daily_loss_today: daily_loss, deployment_policy: {
                                               alloc_pct: 0.25,
                                               risk_per_trade_pct: 0.035,
                                               daily_max_loss_pct: 0.060
                                             })
      end

      context 'when daily loss is within limits' do
        let(:daily_loss) { -3_000 } # 3% of 1L

        it 'allows new trades' do
          expect(processor.send(:daily_loss_guard_ok?)).to be true
        end
      end

      context 'when daily loss exceeds limits' do
        let(:daily_loss) { -5_000 } # 5% of 1L, within 6% limit

        it 'allows new trades when within limit' do
          # The daily loss guard checks if loss_today < max_loss
          # -5000 < -6000 (6% of 100K) is true, so it should allow
          expect(processor.send(:daily_loss_guard_ok?)).to be true
        end
      end

      context 'when daily loss exceeds limits' do
        let(:daily_loss) { -7_000 } # 7% of 1L, exceeds 6% limit

        it 'blocks new trades when exceeding limit' do
          # The daily loss guard checks if loss_today.abs < max_loss.abs
          # 7000 < 6000 (6% of 100K) is false, so it should block
          expect(processor.send(:daily_loss_guard_ok?)).to be false
        end
      end
    end
  end

  describe AlertProcessors::Stock do
    let(:instrument) { create(:instrument, underlying_symbol: 'RELIANCE') }
    let(:alert) { create(:alert, instrument: instrument, signal_type: 'long_entry') }
    let(:processor) { described_class.new(alert) }

    before do
      allow(processor).to receive_messages(available_balance: balance, ltp: ltp, min_lot_by_price: min_lot)
    end

    describe '#calculate_quantity!' do
      let(:ltp) { 2500.0 } # ₹2500 per share
      let(:min_lot) { 1 }

      context 'with ₹1L balance and ₹2500/share stock' do
        let(:balance) { 100_000 }

        it 'calculates correct quantity based on allocation and risk constraints' do
          # Allocation: 1L * 0.25 = 25K, 25K / 2.5K = 10 shares
          # Risk: 1L * 0.035 = 3.5K, 2.5K * 0.04 = 100 risk/share, 3.5K / 100 = 35 shares
          # Affordability: 1L / 2.5K = 40 shares
          # Min of [10, 35, 40] = 10 shares

          quantity = processor.calculate_quantity!
          expect(quantity).to eq(10)
        end
      end

      context 'with ₹2L balance and ₹2500/share stock' do
        let(:balance) { 200_000 }

        it 'calculates correct quantity for large account' do
          # Allocation: 2L * 0.20 = 40K, 40K / 2.5K = 16 shares
          # Risk: 2L * 0.030 = 6K, 2.5K * 0.04 = 100 risk/share, 6K / 100 = 60 shares
          # Affordability: 2L / 2.5K = 80 shares
          # Min of [16, 60, 80] = 16 shares

          quantity = processor.calculate_quantity!
          expect(quantity).to eq(16)
        end
      end
    end
  end

  describe AlertProcessors::McxCommodity do
    let(:instrument) { create(:instrument, underlying_symbol: 'CRUDEOIL') }
    let(:alert) { create(:alert, instrument: instrument, signal_type: 'long_entry') }
    let(:processor) { described_class.new(alert) }

    before do
      allow(processor).to receive(:available_balance).and_return(balance)
    end

    describe '#calculate_quantity' do
      let(:strike) { { strike_price: 5250, last_price: 100.0 } }
      let(:lot_size) { 100 } # CRUDEOIL lot size

      context 'with ₹1L balance and ₹10K/lot commodity' do
        let(:balance) { 100_000 }

        it 'calculates correct quantity for commodity trading' do
          # Allocation: 1L * 0.25 = 25K, 25K / 10K = 2 lots
          # Risk: 1L * 0.035 = 3.5K, 10K * 0.05 = 500 risk/lot, 3.5K / 500 = 7 lots
          # Affordability: 1L / 10K = 10 lots
          # Min of [2, 7, 10] = 2 lots

          quantity = processor.send(:calculate_quantity, strike, lot_size)
          expect(quantity).to eq(200) # 2 lots * 100 lot_size
        end
      end
    end
  end

  describe 'Environment variable overrides' do
    let(:processor) { AlertProcessors::Index.new(create(:alert)) }
    let(:balance) { 100_000 }

    before do
      allow(processor).to receive(:available_balance).and_return(balance)
    end

    context 'with ALLOC_PCT override' do
      before { ENV['ALLOC_PCT'] = '0.40' }
      after { ENV.delete('ALLOC_PCT') }

      it 'uses environment override for allocation' do
        policy = processor.send(:deployment_policy, balance)
        expect(policy[:alloc_pct]).to eq(0.40)
      end
    end

    context 'with RISK_PER_TRADE_PCT override' do
      before { ENV['RISK_PER_TRADE_PCT'] = '0.02' }
      after { ENV.delete('RISK_PER_TRADE_PCT') }

      it 'uses environment override for risk per trade' do
        policy = processor.send(:deployment_policy, balance)
        expect(policy[:risk_per_trade_pct]).to eq(0.02)
      end
    end
  end
end
