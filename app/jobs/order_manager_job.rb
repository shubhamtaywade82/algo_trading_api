# frozen_string_literal: true

class OrderManagerJob < ApplicationJob
  queue_as :default

  def perform
    Managers::Orders::Processor.call
  end
end
