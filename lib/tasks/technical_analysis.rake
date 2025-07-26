namespace :technical_analysis do
  desc 'Fetch & store ATR/TA for indices'
  task update: :environment do
    UpdateTechnicalAnalysisJob.perform_now
  end
end