# frozen_string_literal: true

module RateLimiter
  class Limiter
    def initialize(limit_per_second, daily_limit = nil)
      @limit_per_second = limit_per_second
      @daily_limit = daily_limit
      @request_count = 0
      @daily_request_count = 0
      @queue = Queue.new
      @mutex = Mutex.new
      @last_reset_time = Time.zone.now
      @last_second_time = Time.zone.now

      # Start a thread to process queued requests
      Thread.new { process_queue }
    end

    def call(&block)
      @mutex.synchronize do
        reset_limits if Time.zone.now - @last_reset_time >= 1 # Reset every second
        reset_daily_limit if @daily_limit && Time.zone.now.strftime('%Y-%m-%d') != @last_reset_time.strftime('%Y-%m-%d')

        if @request_count < @limit_per_second && (@daily_limit.nil? || @daily_request_count < @daily_limit)
          @request_count += 1
          @daily_request_count += 1 if @daily_limit
          yield
        else
          @queue << block
        end
      end
    end

    private

    def reset_limits
      @request_count = 0
      @last_reset_time = Time.zone.now
    end

    def reset_daily_limit
      @daily_request_count = 0
    end

    def process_queue
      loop do
        sleep(1.0 / @limit_per_second)
        next if @queue.empty?

        @mutex.synchronize do
          reset_limits if Time.zone.now - @last_reset_time >= 1
          if @request_count < @limit_per_second
            block = @queue.pop
            @request_count += 1
            block.call
          end
        end
      end
    end
  end
end
