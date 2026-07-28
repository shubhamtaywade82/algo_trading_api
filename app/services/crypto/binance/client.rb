# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module Crypto
  module Binance
    class Error < StandardError; end
    class GeoblockedError < Error; end

    # Read-only client for Binance USD-M futures market data.
    #
    # Every endpoint used here is public — klines, ticker and mark price carry
    # no signature and need no API key, which is the whole point: this scanner
    # analyses and notifies, it never trades. There is deliberately no signed
    # request path in this class, so a leaked deploy cannot place an order
    # through it.
    class Client
      DEFAULT_BASES = %w[
        https://fapi.binance.com
        https://fapi1.binance.com
        https://fapi2.binance.com
        https://fapi3.binance.com
      ].freeze
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 10
      MAX_ATTEMPTS = 3

      # Binance caps klines at 1500 per request.
      MAX_LIMIT = 1500

      def initialize(base_url: nil)
        @configured_base = base_url || ENV['CRYPTO_BINANCE_BASE'].presence
      end

      def base_urls
        return [@configured_base.chomp('/')] if @configured_base.present?

        DEFAULT_BASES
      end

      # @param symbol [String] e.g. "SOLUSDT"
      # @param interval [String] e.g. "15m", "4h", "1d"
      # @param limit [Integer] number of bars, oldest first
      # @return [Array<Array>] raw kline rows
      def klines(symbol:, interval:, limit: 200)
        get('/fapi/v1/klines',
            symbol: normalize_symbol(symbol),
            interval: interval,
            limit: [limit.to_i, MAX_LIMIT].min)
      end

      # Convenience wrapper returning a ready-to-analyse {Crypto::Series}.
      def series(symbol:, interval:, limit: 200)
        rows = klines(symbol: symbol, interval: interval, limit: limit)
        Series.from_binance(symbol: normalize_symbol(symbol), timeframe: interval, rows: rows)
      end

      # @return [Float] last traded price
      def last_price(symbol)
        body = get('/fapi/v1/ticker/price', symbol: normalize_symbol(symbol))
        body['price'].to_f
      end

      # @return [Hash] mark price, index price and current funding rate
      def premium_index(symbol)
        get('/fapi/v1/premiumIndex', symbol: normalize_symbol(symbol))
      end

      # Accepts "SOLUSDT", "solusdt", "SOL/USDT" or "SOL-USDT".
      def normalize_symbol(symbol)
        symbol.to_s.upcase.gsub(%r{[/\-_ ]}, '')
      end

      private

      def get(path, **params)
        last_error = nil

        base_urls.each do |base|
          uri = URI.join(base, path)
          uri.query = URI.encode_www_form(params.compact)

          begin
            body = request_with_retries(uri)
            return JSON.parse(body)
          rescue GeoblockedError => e
            last_error = e
            next
          end
        end

        raise last_error if last_error

        raise Error, "Binance request failed for #{path}"
      rescue JSON::ParserError => e
        raise Error, "Binance returned unparseable JSON from #{path}: #{e.message}"
      end

      def request_with_retries(uri)
        attempt = 0
        begin
          attempt += 1
          perform(uri)
        rescue Error
          # An API-level rejection (bad symbol, bad interval) fails identically
          # on every attempt; only transport faults are worth retrying.
          raise
        rescue StandardError => e
          raise Error, "Binance request failed after #{attempt} attempts: #{e.class} - #{e.message}" if attempt >= MAX_ATTEMPTS

          sleep(0.4 * attempt)
          retry
        end
      end

      def perform(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT

        response = http.request(Net::HTTP::Get.new(uri))
        return response.body if response.is_a?(Net::HTTPSuccess)

        if response.code.to_i == 451 || response.body.to_s.include?('restricted location')
          raise GeoblockedError, "Binance #{uri.path} responded 451 (Restricted Location). Datacenter IP is geoblocked."
        end

        raise Error, "Binance #{uri.path} responded #{response.code}: #{response.body.to_s.truncate(200)}"
      end
    end
  end
end
