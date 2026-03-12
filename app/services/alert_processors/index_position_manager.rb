# frozen_string_literal: true

module AlertProcessors
  # Manages the validation, fetching, and closing of open positions for Index alerts.
  class IndexPositionManager < ApplicationService
    def initialize(processor)
      @processor = processor
    end

    def exit_position!(type)
      positions = open_positions_for_type(type)

      if positions.empty?
        @processor.send(:skip!, "no #{type.upcase} position to exit")
        return false
      end

      close_positions(positions, type, 'closed', 'EXIT', "📤 Exited #{type.upcase} position(s) for Alert ##{@processor.alert.id}")

      @processor.alert.update!(status: :processed, error_message: "exited #{type.upcase}")
      false
    end

    def close_opposite!(type)
      positions = open_positions_for_type(type)
      return if positions.empty?

      msg = "↔️ Closed opposite #{type.upcase} position(s) before new entry (Alert ##{@processor.alert.id})"
      close_positions(positions, type, 'Flipped & closed', 'FLIP', msg)
    end

    def open_long_ce_position?
      open_long_position?(ce_security_ids)
    end

    def open_long_pe_position?
      open_long_position?(pe_security_ids)
    end

    private

    def open_positions_for_type(type)
      ids = type == :ce ? ce_security_ids : pe_security_ids
      @processor.dhan_positions.select do |p|
        p_hash = p.is_a?(Hash) ? p : p.to_h
        position_type = p_hash['positionType'] || p_hash[:position_type] || p_hash['position_type']
        security_id = p_hash['securityId'] || p_hash[:security_id] || p_hash['security_id']
        position_type == 'LONG' && ids.include?(security_id.to_s)
      end
    end

    def close_positions(positions, type, log_prefix, tag, notify_msg)
      positions.each do |pos|
        pos_hash = pos.is_a?(Hash) ? pos : pos.to_h
        sec_id = pos_hash['securityId'] || pos_hash[:security_id]
        qty = pos_hash['quantity'] || pos_hash[:quantity]

        payload = {
          transaction_type: 'SELL',
          order_type: 'MARKET',
          product_type: 'MARGIN',
          validity: 'DAY',
          security_id: sec_id,
          exchange_segment: pos_hash['exchangeSegment'] || pos_hash[:exchange_segment],
          quantity: qty
        }

        result = Orders::Gateway.place_order(payload, source: self.class.name)
        if result[:dry_run]
          @processor.send(:log, :warn, "blocked #{type.upcase} exit ⇒ security_id=#{sec_id}, quantity=#{qty}")
          next
        end

        @processor.send(:log, :info, "#{log_prefix} #{type.upcase} ⇒ security_id=#{sec_id}, quantity=#{qty}")
        @processor.send(:notify, notify_msg, tag: tag)
      end
    end

    def open_long_position?(sec_ids)
      @processor.dhan_positions.any? do |p|
        p_hash = p.is_a?(Hash) ? p : p.to_h
        position_type = p_hash['positionType'] || p_hash[:position_type] || p_hash['position_type']
        security_id = p_hash['securityId'] || p_hash[:security_id] || p_hash['security_id']
        position_type == 'LONG' && sec_ids.include?(security_id.to_s)
      end
    end

    def ce_security_ids
      @ce_security_ids ||= @processor.instrument.derivatives.where(option_type: 'CE').pluck(:security_id).map(&:to_s)
    end

    def pe_security_ids
      @pe_security_ids ||= @processor.instrument.derivatives.where(option_type: 'PE').pluck(:security_id).map(&:to_s)
    end
  end
end
