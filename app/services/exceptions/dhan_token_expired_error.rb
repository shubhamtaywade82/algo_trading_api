# frozen_string_literal: true

module Exceptions
  # Raised when Dhan access token is expired and trading must halt.
  class DhanTokenExpiredError < StandardError
    MESSAGE = 'Dhan access token expired — trading halted. Re-login at /auth/dhan/login'

    def initialize
      super(MESSAGE)
    end
  end
end
