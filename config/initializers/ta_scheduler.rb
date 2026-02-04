START_TIME = Time.zone.parse('09:10')
END_TIME = Time.zone.parse('15:30')

if ENV['ENABLE_TA_LOOP'] == 'true'
  Rails.application.config.after_initialize do
    begin
      next unless ActiveRecord::Base.connection.table_exists?('dhan_access_tokens')

      Thread.new do
        loop do
          if Time.zone.now > START_TIME && Time.zone.now < END_TIME && DhanAccessToken.valid?
            UpdateTechnicalAnalysisJob.perform_later
          end
          sleep 3.minutes
        end
      end
    rescue ActiveRecord::DatabaseConnectionError => e
      Rails.logger.warn "[TA Scheduler] Database unreachable, TA loop not started: #{e.message}"
    end
  end
end