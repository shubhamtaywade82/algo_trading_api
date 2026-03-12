# frozen_string_literal: true

module AI
  module Tools
    # Queries trade history and exit logs for operator/debugging agents.
    class TradeLogTool < BaseTool
      TOOL_NAME   = 'get_trade_logs'
      DESCRIPTION = 'Fetch trade execution logs, order history, and exit events. Useful for debugging why a trade was placed, modified, or closed.'
      PARAMETERS  = {
        type: 'object',
        properties: {
          symbol: {
            type: 'string',
            description: 'Filter by trading symbol (optional)'
          },
          limit: {
            type: 'integer',
            description: 'Maximum number of log entries to return (default 20, max 50)'
          },
          since_hours: {
            type: 'integer',
            description: 'Only return logs from the last N hours (default 24)'
          },
          include_exit_logs: {
            type: 'boolean',
            description: 'Include exit log entries (default true)'
          },
          include_orders: {
            type: 'boolean',
            description: 'Include order records (default true)'
          },
          include_alerts: {
            type: 'boolean',
            description: 'Include TradingView alert records (default false)'
          }
        },
        required: []
      }.freeze

      def perform(args)
        symbol            = args['symbol']&.upcase
        limit             = [args['limit'].to_i.positive? ? args['limit'].to_i : 20, 50].min
        since_hours       = args['since_hours'].to_i.positive? ? args['since_hours'].to_i : 24
        include_exits     = args.fetch('include_exit_logs', true)
        include_orders    = args.fetch('include_orders', true)
        include_alerts    = args.fetch('include_alerts', false)

        since_time = Time.current - since_hours.hours

        result = {}

        if include_exits
          exits_scope = ExitLog.where('created_at >= ?', since_time).order(created_at: :desc)
          exits_scope = exits_scope.where(trading_symbol: symbol) if symbol
          result[:exit_logs] = exits_scope.limit(limit).map { |e| format_exit_log(e) }
        end

        if include_orders
          orders_scope = Order.where('created_at >= ?', since_time).order(created_at: :desc)
          orders_scope = orders_scope.where(trading_symbol: symbol) if symbol
          result[:orders] = orders_scope.limit(limit).map { |o| format_order(o) }
        end

        if include_alerts
          alerts_scope = Alert.where('created_at >= ?', since_time).order(created_at: :desc)
          alerts_scope = alerts_scope.where("data->>'symbol' = ?", symbol) if symbol
          result[:alerts] = alerts_scope.limit(limit).map { |a| format_alert(a) }
        end

        result.merge(
          symbol:      symbol || 'all',
          since:       since_time.strftime('%Y-%m-%dT%H:%M:%S%z'),
          timestamp:   Time.current.strftime('%Y-%m-%dT%H:%M:%S%z')
        )
      rescue StandardError => e
        { error: e.message }
      end

      private

      def format_exit_log(e)
        {
          id:             e.id,
          symbol:         e.trading_symbol,
          reason:         e.exit_reason,
          pnl:            e.try(:pnl)&.to_f&.round(2),
          quantity:       e.try(:quantity),
          exit_price:     e.try(:exit_price)&.to_f&.round(2),
          created_at:     e.created_at.strftime('%Y-%m-%dT%H:%M:%S%z')
        }
      end

      def format_order(o)
        {
          id:               o.id,
          dhan_order_id:    o.try(:dhan_order_id) || o.try(:order_id),
          symbol:           o.try(:trading_symbol),
          transaction_type: o.try(:transaction_type),
          product_type:     o.try(:product_type),
          quantity:         o.try(:quantity),
          price:            o.try(:price)&.to_f&.round(2),
          status:           o.try(:order_status),
          created_at:       o.created_at.strftime('%Y-%m-%dT%H:%M:%S%z')
        }
      end

      def format_alert(a)
        {
          id:          a.id,
          data:        a.data,
          processed:   a.try(:processed),
          created_at:  a.created_at.strftime('%Y-%m-%dT%H:%M:%S%z')
        }
      end
    end
  end
end
