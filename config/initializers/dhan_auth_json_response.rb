# frozen_string_literal: true

require 'json'
require 'dhan_hq'

# ------------------------------------------------------------
# DhanHQ 3.2.x: auth responses are never parsed
# ------------------------------------------------------------
#
# `DhanHQ::Auth.build_connection` sets Faraday up with `request :url_encoded`
# and an adapter only — there is no JSON *response* middleware, so Faraday
# hands the body back as a raw String. The SDK's own `handle_response` then
# ends with:
#
#     response.body.is_a?(Hash) ? response.body : {}
#
# so every *successful* call to `generate_access_token` / `renew_token` returns
# an empty Hash, and the accessToken goes into the bin with the body. On boot
# that surfaced as a token that could never be generated:
#
#     [DHAN] Regenerating token via TOTP...
#     [DHAN] Token bootstrap skipped: DhanHQ::InvalidAuthenticationError -
#       Dhan token response missing accessToken. Keys: []
#
# The empty key list is the tell: the HTTP call had already succeeded, there
# was simply nothing left of the response by the time Dhan::TokenManager read
# it. Nothing environment-specific — the auth path cannot return a token on
# any host.
#
# The main REST client is unaffected; it decodes through
# DhanHQ::Helpers::ResponseHelper. Only the auth path skips the step, so decode
# the body before the SDK inspects it. The failure path improves for free: it
# can now find `errorMessage` in the payload instead of dumping the raw string,
# turning `GenerateAccessToken failed: 401 {"errorMessage":"Invalid TOTP"}`
# into `GenerateAccessToken failed: 401 Invalid TOTP`.
#
# Remove once the gem parses its own auth responses.
module DhanHQ
  # Decodes JSON auth bodies before DhanHQ::Auth inspects them.
  module AuthJsonResponse
    def handle_response(response, context:)
      env = response.env
      env.body = decode(env.body) if env.respond_to?(:body=) && env.body.is_a?(String)

      super
    end

    private

    # Parses a JSON object body, leaving anything else — HTML error pages, an
    # empty body, a bare JSON array — untouched so the SDK still reports it.
    def decode(body)
      return body if body.strip.empty?

      parsed = JSON.parse(body)
      parsed.is_a?(Hash) ? parsed : body
    rescue JSON::ParserError
      body
    end
  end
end

DhanHQ::Auth.singleton_class.prepend(DhanHQ::AuthJsonResponse)
