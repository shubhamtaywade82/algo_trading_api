# frozen_string_literal: true

class PaperOneMinuteSignalJob < ApplicationJob
  queue_as :default

  def perform
    Market::OneMinutePaperTrader.call
  end
end

