class UpdateTechnicalAnalysisJob < ApplicationJob
  queue_as :default # works with delayed_job or :async

  def perform
    Market::AnalysisUpdater.call
  end
end