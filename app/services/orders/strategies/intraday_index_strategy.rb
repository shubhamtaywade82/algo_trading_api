module Orders
  module Strategies
    class IntradayIndexStrategy < IntradayOptionsStrategy
      private

      def determine_option_type(action)
        # Index uses CALL/PUT
        super
      end
    end
  end
end
