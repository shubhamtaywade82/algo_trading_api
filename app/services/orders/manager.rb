# frozen_string_literal: true

module Orders
  class Manager < ApplicationService
    def self.place(params)
      response = Dhanhq::API::Orders.place(params)
      raise "Order placement failed: #{response['error']}" unless response['status'] == 'success'

      response
    end
  end
end
