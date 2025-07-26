if Rails.env.development? && ENV['ENABLE_TA_LOOP'] == 'true'
  Rails.application.config.after_initialize do
    Thread.new do
      loop do
        # Loads fine because autoloading is finished
        UpdateTechnicalAnalysisJob.perform_later
        sleep 5.minutes
      end
    end
  end
end