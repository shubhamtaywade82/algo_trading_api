# frozen_string_literal: true

module Crypto
  # Renders a {Setup} as the Telegram message a human reads on their phone.
  #
  # Plain text with emoji rather than Markdown or HTML: a symbol or a level
  # never needs escaping, so a stray underscore in a future pair name cannot
  # make Telegram reject the whole message. The order is the order the trade
  # is taken in — what, where, how much risk, then why.
  class SetupFormatter
    def self.call(...) = new(...).call

    def initialize(setup)
      @setup = setup
    end

    def call
      [header, levels, context, confluence, footer].compact.join("\n\n")
    end

    private

    attr_reader :setup

    def header
      arrow = setup.long? ? '🟢 LONG' : '🔴 SHORT'
      "#{arrow}  #{setup.symbol}\n" \
        "SMC / ICT setup · grade #{setup.grade} · score #{setup.score}/100"
    end

    def levels
      lines = [
        "🎯 Entry   #{fmt(setup.entry)}",
        "🛑 Stop    #{fmt(setup.stop)}   (#{Formatting.move_percent(setup.entry, setup.stop)})",
        "✅ TP1     #{fmt(setup.target1)}   (#{Formatting.move_percent(setup.entry, setup.target1)})"
      ]
      lines << "✅ TP2     #{fmt(setup.target2)}   (#{Formatting.move_percent(setup.entry, setup.target2)})" if setup.target2
      lines << "⚖️ Risk    #{fmt(setup.risk)} per unit · R:R #{setup.risk_reward}"
      lines.join("\n")
    end

    def context
      bias = setup.context[:bias] || {}
      order = %w[1d 4h 1h 15m 5m]
      line = order.filter_map { |tf| "#{tf} #{arrow_for(bias[tf])}" if bias.key?(tf) }.join('  ')
      return nil if line.blank?

      "🧭 Bias\n#{line}\nRange: #{setup.context[:range_zone] || 'n/a'}"
    end

    def confluence
      return nil if setup.confluences.blank?

      body = setup.confluences.map { |c| "• #{c[:label]}" }.join("\n")
      "📋 Confluence\n#{body}"
    end

    def footer
      "🕒 #{setup.generated_at.in_time_zone('Asia/Kolkata').strftime('%d %b %Y %H:%M %Z')}\n" \
        'Analysis only — no order was placed.'
    end

    def arrow_for(bias)
      case bias
      when :bullish then '↑'
      when :bearish then '↓'
      else '→'
      end
    end

    # Named `fmt` rather than `p`, which would shadow Kernel#p.
    def fmt(value) = Formatting.price(value)
  end
end
