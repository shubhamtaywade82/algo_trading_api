# frozen_string_literal: true

class Quote < ApplicationRecord
  belongs_to :instrument

  # If you want to validate presence:
  validates :ltp, :tick_time, presence: true

  # Optional: deserialize metadata keys for easy access
  store_accessor :metadata, :oi, :depth

  # scope for recent quotes
  scope :recent, -> { order(tick_time: :desc) }

  # Optional: method to format the quote for display
  def formatted_quote
    "#{instrument.symbol_name} - LTP: #{PriceMath.round_tick(ltp)}, Volume: #{volume}, Time: #{tick_time.strftime('%H:%M:%S')}"
  end
end
