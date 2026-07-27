# frozen_string_literal: true

require 'rails_helper'

# Guards config/initializers/dhan_auth_json_response.rb.
#
# DhanHQ 3.2.x builds its auth connection without JSON response middleware, so
# Faraday returns the body as a String and the SDK's `handle_response` reduces
# it to `{}`. Every spec that touches token generation stubs `DhanHQ::Auth`
# itself and returns a Hash, so nothing in the suite crossed the one boundary
# where the token was actually being lost. These examples stub HTTP instead.
RSpec.describe 'DhanHQ auth JSON responses' do
  let(:auth_url) { 'https://auth.dhan.co/app/generateAccessToken' }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }

  def generate_token
    DhanHQ::Auth.generate_access_token(dhan_client_id: '1101', pin: '1234', totp: '123456')
  end

  describe '.generate_access_token' do
    it 'returns the decoded body rather than an empty hash' do
      stub_request(:post, /auth\.dhan\.co/).to_return(
        status: 200,
        body: { dhanClientId: '1101', accessToken: 'jwt.token.value',
                expiryTime: '2026-07-28T13:29:00' }.to_json,
        headers: json_headers
      )

      expect(generate_token).to include(
        'accessToken' => 'jwt.token.value',
        'expiryTime' => '2026-07-28T13:29:00'
      )
    end

    it 'decodes the body even when Dhan omits a JSON content type' do
      stub_request(:post, /auth\.dhan\.co/).to_return(
        status: 200,
        body: { accessToken: 'jwt.token.value', expiryTime: '2026-07-28T13:29:00' }.to_json,
        headers: { 'Content-Type' => 'text/plain' }
      )

      expect(generate_token['accessToken']).to eq('jwt.token.value')
    end

    it 'surfaces the broker error message on a failed handshake' do
      stub_request(:post, /auth\.dhan\.co/).to_return(
        status: 401,
        body: { errorMessage: 'Invalid TOTP' }.to_json,
        headers: json_headers
      )

      expect { generate_token }
        .to raise_error(DhanHQ::InvalidAuthenticationError, /401 Invalid TOTP/)
    end

    it 'leaves a non-JSON error body for the SDK to report verbatim' do
      stub_request(:post, /auth\.dhan\.co/).to_return(
        status: 502,
        body: '<html><body>Bad Gateway</body></html>',
        headers: { 'Content-Type' => 'text/html' }
      )

      expect { generate_token }
        .to raise_error(DhanHQ::InvalidAuthenticationError, /502.*Bad Gateway/m)
    end

    it 'does not blow up on an empty body' do
      stub_request(:post, /auth\.dhan\.co/).to_return(status: 200, body: '', headers: json_headers)

      expect(generate_token).to eq({})
    end
  end
end
