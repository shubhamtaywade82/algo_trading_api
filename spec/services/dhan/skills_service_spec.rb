# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dhan::SkillsService do
  around do |example|
    orig_place_order = ENV.fetch('PLACE_ORDER', nil)
    orig_live_trading = ENV.fetch('LIVE_TRADING', nil)
    example.run
  ensure
    ENV['PLACE_ORDER'] = orig_place_order
    ENV['LIVE_TRADING'] = orig_live_trading
  end

  def disable_placement!
    ENV['PLACE_ORDER'] = 'false'
    ENV['LIVE_TRADING'] = 'false'
  end

  def enable_placement!
    ENV['PLACE_ORDER'] = 'true'
    ENV['LIVE_TRADING'] = 'true'
  end

  describe '.catalogue' do
    it 'lists the SDK builtin skills with risk metadata' do
      names = described_class.catalogue.pluck(:name)

      expect(names).to include('iron_condor', 'straddle', 'square_off_all')
    end

    it 'flags the destructive skills as writes' do
      writes = described_class.catalogue.select { |s| s[:write] }.pluck(:name)

      expect(writes).to contain_exactly('square_off_all', 'square_off_position')
    end

    it 'marks writes unpermitted while the switches are off' do
      disable_placement!

      square_off = described_class.catalogue.find { |s| s[:name] == 'square_off_all' }
      condor = described_class.catalogue.find { |s| s[:name] == 'iron_condor' }

      expect(square_off[:permitted]).to be(false)
      expect(condor[:permitted]).to be(true)
    end

    it 'permits writes once both switches are on' do
      enable_placement!

      square_off = described_class.catalogue.find { |s| s[:name] == 'square_off_all' }

      expect(square_off[:permitted]).to be(true)
    end
  end

  describe '.write_skill?' do
    it 'identifies destructive and analytical skills' do
      expect(described_class.write_skill?('square_off_all')).to be(true)
      expect(described_class.write_skill?('iron_condor')).to be(false)
    end

    it 'is false for an unknown skill' do
      expect(described_class.write_skill?('nope')).to be(false)
    end
  end

  describe '.call' do
    # square_off_all calls Position.exit_all! directly, bypassing
    # Orders::Gateway, so the gate has to live here.
    it 'blocks a destructive skill when placement is disabled' do
      disable_placement!
      allow(DhanHQ::Skills::Registry).to receive(:call)

      result = described_class.call('square_off_all')

      expect(result).to include(ok: false, blocked: true, dry_run: true)
      expect(DhanHQ::Skills::Registry).not_to have_received(:call)
    end

    it 'runs a destructive skill when both switches are on' do
      enable_placement!
      allow(DhanHQ::Skills::Registry).to receive(:call).and_return(exited_count: 2)

      result = described_class.call('square_off_all')

      expect(result).to include(ok: true)
      expect(result[:result]).to eq(exited_count: 2)
    end

    it 'runs an analytical skill regardless of the switches' do
      disable_placement!
      allow(DhanHQ::Skills::Registry).to receive(:call).and_return(legs: [])

      result = described_class.call('iron_condor', symbol: 'NIFTY')

      expect(result).to include(ok: true, skill: 'iron_condor')
    end

    it 'reports an unknown skill without raising' do
      expect(described_class.call('does_not_exist')).to include(ok: false, error: 'unknown_skill')
    end

    it 'surfaces a risk-pipeline rejection distinctly' do
      enable_placement!
      allow(DhanHQ::Skills::Registry).to receive(:call).and_raise(DhanHQ::RiskViolation.new('limit breached'))

      expect(described_class.call('square_off_all')).to include(ok: false, error: 'risk_violation')
    end

    it 'contains an arbitrary skill failure' do
      disable_placement!
      allow(DhanHQ::Skills::Registry).to receive(:call).and_raise(StandardError, 'boom')

      expect(described_class.call('iron_condor')).to include(ok: false, error: 'skill_failed')
    end
  end
end
