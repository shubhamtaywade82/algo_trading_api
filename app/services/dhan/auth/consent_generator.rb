# frozen_string_literal: true

module Dhan
  module Auth
    # STEP 1 of Dhan API key flow: generate consent and return consentAppId for browser login.
    # See: https://auth.dhan.co/app/generate-consent
    class ConsentGenerator
      BASE = 'https://auth.dhan.co'

      def self.call
        new.call
      end

      def call
        raise 'DHAN_API_KEY and DHAN_API_SECRET are required for Dhan login' if app_id.blank? || app_secret.blank?

        response = post_generate_consent
        body = JSON.parse(response.body, symbolize_names: true)

        raise_consent_error(body) unless response.is_a?(Net::HTTPSuccess)

        body[:consentAppId] || body[:consent_app_id]
      end

      private

      def post_generate_consent
        uri = URI("#{BASE}/app/generate-consent?client_id=#{client_id}")
        req = Net::HTTP::Post.new(uri)
        req['app_id'] = app_id
        req['app_secret'] = app_secret

        Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
      end

      def client_id
        ENV.fetch('DHAN_CLIENT_ID', nil) || ENV.fetch('CLIENT_ID', nil)
      end

      def app_id
        ENV.fetch('DHAN_API_KEY', nil)
      end

      def app_secret
        ENV.fetch('DHAN_API_SECRET', nil)
      end

      def raise_consent_error(body)
        message = body[:message] || body[:error] || body.to_s
        raise "Dhan consent generation failed: #{message}"
      end
    end
  end
end
