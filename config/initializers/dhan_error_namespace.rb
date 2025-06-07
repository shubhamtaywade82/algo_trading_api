module Dhanhq
  module Errors
    class RateLimit < StandardError
      attr_reader :retry_after

      def initialize(msg = 'Too Many Requests', retry_after: nil)
        @retry_after = retry_after
        super(msg)
      end
    end
  end
end