# frozen_string_literal: true

module Mcp
  module Tools
    # Tool that modifies an existing position via Trading::PositionManager.
    class ManagePosition
      def self.name
        'manage_position'
      end

      def self.definition
        {
          name: name,
          title: 'Manage Position',
          description: 'Moves SL to break-even, trails SL, books partial profits, or force exits.',
          inputSchema: {
            type: 'object',
            properties: {
              security_id: { type: 'string', description: 'Dhan security ID' },
              exchange_segment: { type: 'string', description: 'e.g. NSE_FNO' },
              action: {
                type: 'string',
                description: 'Action to perform',
                enum: %w[move_sl_to_be trail_sl partial_exit force_exit]
              },
              trail_pct: { type: 'number', description: 'Optional trail percentage (only for trail_sl)' }
            },
            required: %w[security_id exchange_segment action]
          }
        }
      end

      def self.execute(args)
        opts = args.with_indifferent_access
        security_id = opts[:security_id].to_s
        exchange_segment = opts[:exchange_segment].to_s
        action = opts[:action].to_s

        validate!(security_id: security_id, exchange_segment: exchange_segment, action: action)

        params = {}
        if opts.key?(:trail_pct) && opts[:trail_pct].present?
          params[:trail_pct] = opts[:trail_pct].to_f
        end

        result = Trading::PositionManager.call(
          security_id: security_id,
          exchange_segment: exchange_segment,
          action: action.to_sym,
          params: params
        )

        result.to_h
      rescue StandardError => e
        { error: e.message }
      end

      class << self
        private

        def validate!(security_id:, exchange_segment:, action:)
          raise ArgumentError, 'security_id is required' if security_id.blank?
          raise ArgumentError, 'exchange_segment is required' if exchange_segment.blank?
          raise ArgumentError, 'action is required' if action.blank?
          raise ArgumentError, 'unsupported action' unless %w[move_sl_to_be trail_sl partial_exit force_exit].include?(action)
        end
      end
    end
  end
end

