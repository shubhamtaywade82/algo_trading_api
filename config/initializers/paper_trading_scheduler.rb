# frozen_string_literal: true

paper_start_time = Time.zone.parse('09:10')
paper_end_time = Time.zone.parse('15:30')

if ENV['ENABLE_PAPER_TRADING_LOOP'] == 'true'
  Rails.application.config.after_initialize do
    Thread.new do
      loop do
        now = Time.zone.now
        if now > paper_start_time && now < paper_end_time
          PaperOneMinuteSignalJob.perform_later
          PaperPositionsManagerJob.perform_later
        end
        sleep 60
      end
    end
  end
end

