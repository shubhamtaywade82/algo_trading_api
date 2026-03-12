# frozen_string_literal: true

module AI
  module Tools
    # Queries trade history and exit logs for operator/debugging agents.
    class TradeLogTool < ::Agents::Tool
      description 'Fetch trade execution logs, order history, and exit events. Useful for debugging why a trade was placed, modified, or closed.'

      param :symbol,             type: 'string',  desc: 'Filter by trading symbol (optional)', required: false
      param :limit,              type: 'integer', desc: 'Max log entries to return (default 20, max 50)', required: false
      param :since_hours,        type: 'integer', desc: 'Only return logs from the last N hours (default 24)', required: false
      param :include_exit_logs,  type: 'boolean', desc: 'Include exit log entries (default true)', required: false
      param :include_orders,     type: 'boolean', desc: 'Include order records (default true)', required: false
      param :include_alerts,     type: 'boolean', desc: 'Include TradingView alert records (default false)', required: false

      def perform(_ctx, symbol: nil, limit: 20, since_hours: 24, include_exit_logs: true, include_orders: true, include_alerts: false)
        sym        = symbol&.upcase
        lim        = [limit.to_i.positive? ? limit.to_i : 20, 50].min
        since_time = Time.current - since_hours.to_i.positive? ? since_hours.to_i.hours : 24.hours

        result = {}

        if include_exit_logs
          scope = ExitLog.where('created_at >= ?', since_time).order(created_at: :desc)
          scope = scope.where(trading_symbol: sym) if sym
          result[:exit_logs] = scope.limit(lim).map { |e| format_exit_log(e) }
        end

        if include_orders
          scope = Order.where('created_at >= ?', since_time).order(created_at: :desc)
          scope = scope.where(trading_symbol: sym) if sym
          result[:orders] = scope.limit(lim).map { |o| format_order(o) }
        end

        if include_alerts
          scope = Alert.where('created_at >= ?', since_time).order(created_at: :desc)
          scope = scope.where("data->>'symbol' = ?", sym) if sym
          result[:alerts] = scope.limit(lim).map { |a| format_alert(a) }
        end

        result.merge(
          symbol:    sym || 'all',
          since:     since_time.strftime('%Y-%m-%dT%H:%M:%S%z'),
          timestamp: Time.current.strftime('%Y-%m-%dT%H:%M:%S%z')
        )
      rescue StandardError => e
        { error: e.message }
      end

      private

      def format_exit_log(e)
        {
          id:         e.id,
          symbol:     e.trading_symbol,
          reason:     e.exit_reason,
          pnl:        e.try(:pnl)&.to_f&.round(2),
          exit_price: e.try(:exit_price)&.to_f&.round(2),
          created_at: e.created_at.strftime('%Y-%m-%dT%H:%M:%S%z')
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
          id:         a.id,
          data:       a.data,
          processed:  a.try(:processed),
          created_at: a.created_at.strftime('%Y-%m-%dT%H:%M:%S%z')
        }
      end
    end
  end
end
