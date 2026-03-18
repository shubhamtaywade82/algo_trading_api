# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::Tools::ManagePosition do
  describe '.execute' do
    it 'delegates to Trading::PositionManager and returns result hash' do
      result_struct = Trading::PositionManager::Result.new(
        success: true,
        action: :move_sl_to_be,
        message: 'SL moved to break-even',
        details: { new_trigger_price: 120.0 }
      )

      expect(Trading::PositionManager).to receive(:call).with(
        security_id: '1333',
        exchange_segment: 'NSE_FNO',
        action: :move_sl_to_be,
        params: {}
      ).and_return(result_struct)

      result = described_class.execute(
        'security_id' => '1333',
        'exchange_segment' => 'NSE_FNO',
        'action' => 'move_sl_to_be'
      )

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:move_sl_to_be)
      expect(result[:details][:new_trigger_price]).to eq(120.0)
    end

    it 'passes trail_pct into params for trail_sl' do
      result_struct = Trading::PositionManager::Result.new(
        success: true,
        action: :trail_sl,
        message: 'SL trailed',
        details: { new_trigger_price: 130.0 }
      )

      expect(Trading::PositionManager).to receive(:call).with(
        security_id: '1333',
        exchange_segment: 'NSE_FNO',
        action: :trail_sl,
        params: { trail_pct: 3.0 }
      ).and_return(result_struct)

      result = described_class.execute(
        'security_id' => '1333',
        'exchange_segment' => 'NSE_FNO',
        'action' => 'trail_sl',
        'trail_pct' => 3.0
      )

      expect(result[:action]).to eq(:trail_sl)
    end
  end
end

