# frozen_string_literal: true

module Dhan
  module Auth
    class TokenExchanger
      URL = 'https://api.dhan.co/v2/token'

      def self.call(code)
        new(code).call
      end

      def initialize(code)
        @code = code
      end

      def call
        response = post_token_request
        body = JSON.parse(response.body, symbolize_names: true)

        raise_token_error(body) unless response.is_a?(Net::HTTPSuccess)

        {
          access_token: body[:accessToken],
          expires_in: body[:expiresIn]
        }
      end

      private

      attr_reader :code

      def post_token_request
        uri = URI(URL)
        req = Net::HTTP::Post.new(uri)
        req['Content-Type'] = 'application/json'
        req.body = payload.to_json

        Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') { |http| http.request(req) }
      end

      def payload
        {
          clientId: client_id,
          clientSecret: client_secret,
          code: code
        }
      end

      def client_id
        ENV.fetch('DHAN_CLIENT_ID', nil) || ENV.fetch('CLIENT_ID', nil)
      end

      def client_secret
        ENV.fetch('DHAN_CLIENT_SECRET', nil) || ENV.fetch('DHAN_API_SECRET', nil)
      end

      def raise_token_error(body)
        message = body[:message] || body[:error] || body.to_s
        raise "Dhan token exchange failed: #{message}"
      end
    end
  end
end
