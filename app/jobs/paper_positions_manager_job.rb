# frozen_string_literal: true

class PaperPositionsManagerJob < ApplicationJob
  queue_as :default

  def perform
    PaperPositions::Manager.call
  end
end

