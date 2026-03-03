# frozen_string_literal: true

module Market
  # Sends a formatted Telegram alert for a ConfluenceSignal.
  # For :high level signals, also enqueues MarketAnalysisJob.
  #
  # Usage:
  #   Market::ConfluenceNotifier.call(signal: signal)
  class ConfluenceNotifier < ApplicationService
    SYMBOL_EXCHANGE = { 'NIFTY' => :nse, 'BANKNIFTY' => :nse, 'SENSEX' => :bse }.freeze
    SEPARATOR       = ("\u2501" * 28).freeze

    def initialize(signal:)
      @signal = signal
    end

    def call
      return if @signal.nil?
      return if ENV['TELEGRAM_CHAT_ID'].blank?

      msg = format_message
      TelegramNotifier.send_message(msg)
      Rails.logger.info "[Confluence] #{@signal.symbol} #{@signal.bias} #{@signal.level} score=#{@signal.net_score}"

      return unless @signal.level == :high

      chat_id  = ENV.fetch('TELEGRAM_CHAT_ID', nil)
      exchange = SYMBOL_EXCHANGE.fetch(@signal.symbol, :nse)
      MarketAnalysisJob.perform_later(chat_id, @signal.symbol, exchange: exchange)
    rescue StandardError => e
      Rails.logger.error "[Confluence] Notify failed: #{e.class}: #{e.message}"
    end

    private

    def format_message
      lines = [header, SEPARATOR, 'Momentum & Trend']
      lines += momentum_lines
      lines += ['', 'Structure (SMC)']
      lines += structure_lines
      lines += ['', 'Price Action']
      lines += price_action_lines
      lines << SEPARATOR
      lines << footer
      lines << "\u{1F50D} High confluence \u2014 detailed analysis queued" if @signal.level == :high
      lines.join("\n")
    end

    def header
      emoji = @signal.bias == :bullish ? "\u{1F7E2}" : "\u{1F534}"
      "#{emoji} #{@signal.symbol} #{@signal.bias.to_s.upcase} CONFLUENCE [#{@signal.net_score.abs}/#{@signal.max_score}]"
    end

    def footer
      ts  = @signal.timestamp.is_a?(Time) ? @signal.timestamp.strftime('%H:%M') : '-'
      atr = @signal.atr ? @signal.atr.round(1).to_s : 'N/A'
      "Close: \u20B9#{fmt_price(@signal.close)} | ATR: #{atr} | #{ts}"
    end

    # ── Section builders ────────────────────────────────────────────────────

    def momentum_lines
      [
        factor_line('SuperTrend', 'SuperTrend'),
        factor_line('MACD', 'MACD'),
        factor_line('RSI', 'RSI'),
        price_ema_line,
        factor_line('ADX', 'ADX')
      ]
    end

    def structure_lines
      [
        factor_line('BOS', 'BOS'),
        factor_line('FVG', 'FVG'),
        factor_line('Liquidity Grab', 'Liquidity grab'),
        factor_line('Order Block', 'Order block')
      ]
    end

    def price_action_lines
      [factor_line('Bollinger', 'Bollinger')]
    end

    # ── Line helpers ─────────────────────────────────────────────────────────

    def factor_line(factor_name, label)
      f = factor_map[factor_name]
      return "\u2B1C #{label}: N/A" unless f

      "#{icon(f.value)} #{label}: #{f.note}"
    end

    def price_ema_line
      v20 = factor_map['EMA20']&.value || 0
      v50 = factor_map['EMA50']&.value || 0

      note = if v20.positive? && v50.positive?
               'above EMA20 & EMA50'
             elsif v20.negative? && v50.negative?
               'below EMA20 & EMA50'
             elsif v20.positive?
               'above EMA20, below EMA50'
             else
               'above EMA50, below EMA20'
             end

      "#{icon(v20 + v50)} Price: #{note}"
    end

    def icon(value)
      if value.zero?
        "\u2B1C"
      elsif (@signal.bias == :bullish && value.positive?) || (@signal.bias == :bearish && value.negative?)
        "\u2705"
      else
        "\u274C"
      end
    end

    def factor_map
      @factor_map ||= @signal.factors.index_by(&:name)
    end

    def fmt_price(val)
      return '0' unless val

      format('%g', val.to_f)
    end
  end
end
