# frozen_string_literal: true

class LevelsUpdateJob < ApplicationJob
  queue_as :default

  def perform
    Rake::Task['levels:update'].invoke
  end
end
