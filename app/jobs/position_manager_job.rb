# frozen_string_literal: true

class PositionsManagerJob < ApplicationJob
  queue_as :default

  def perform
    Managers::Positions.call
  end
end
