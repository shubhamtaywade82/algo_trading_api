# frozen_string_literal: true

module Mcp
  module Tools
    class GetPositions
      def self.name
        'get_positions'
      end

      def self.definition
        {
          name: name,
          title: 'Fetch open trading positions',
          description: 'Returns all active trading positions from DhanHQ.',
          inputSchema: {
            type: 'object',
            properties: {},
            additionalProperties: false
          }
        }
      end

      def self.execute(_args)
        unless ENV['DHAN_CLIENT_ID'].present? || ENV['CLIENT_ID'].present?
          return { error: 'Dhan not configured. Set DHAN_CLIENT_ID and complete login.' }
        end

        positions = DhanHQ::Models::Position.all
        list = positions.is_a?(Array) ? positions : Array(positions)
        list.map { |p| p.respond_to?(:attributes) ? p.attributes : p.to_h }
      rescue StandardError => e
        { error: e.message }
      end
    end
  end
end
