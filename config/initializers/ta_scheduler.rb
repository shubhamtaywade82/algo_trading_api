START_TIME = Time.zone.parse('09:10')
END_TIME = Time.zone.parse('15:30')
if ENV['ENABLE_TA_LOOP'] == 'true'
  Rails.application.config.after_initialize do
    Thread.new do
      loop do
        # Loads fine because autoloading is finished
        UpdateTechnicalAnalysisJob.perform_later if Time.zone.now > START_TIME && Time.zone.now < END_TIME
        sleep 3.minutes
      end
    end
  end
end