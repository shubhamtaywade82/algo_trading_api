# frozen_string_literal: true

module Crypto
  # Price and percentage rendering for notifications.
  #
  # Crypto pairs do not share a tick size — ETHUSDT quotes to two decimals,
  # SOLUSDT to three, and a smaller pair to four or five. Rather than carry a
  # per-symbol tick table for what is only ever display, precision is chosen
  # from the magnitude of the number itself, which gets every USDT perp right
  # without a lookup that could go stale.
  module Formatting
    module_function

    def price(value)
      return '—' if value.nil?

      value = value.to_f
      decimals =
        case value.abs
        when 0...1 then 5
        when 1...20 then 4
        when 20...1_000 then 3
        else 2
        end

      format("%.#{decimals}f", value)
    end

    def percent(value, decimals: 2)
      return '—' if value.nil?

      "#{format("%.#{decimals}f", value.to_f)}%"
    end

    # Signed distance from `from` to `to`, as a percentage of `from`.
    def move_percent(from, to)
      return '—' if from.nil? || to.nil? || from.to_f.zero?

      percent(((to.to_f - from.to_f) / from.to_f) * 100)
    end
  end
end
