# frozen_string_literal: true

module Catalog
  class FactorScoreEngine
    require 'csv'
    require 'open-uri'

    OUTPUT_CSV = Rails.root.join('tmp/factor_scores.csv')

    # Scoring Weights
    WEIGHTS = {
      price_momentum: 2,
      volatility: 2,
      volume_trend: 2,
      moving_average_trend: 2,
      atr_volatility: 2
    }.freeze

    # Rate Limits (per second for Data APIs)
    RATE_LIMIT = 5

    def self.call
      new.call
    end

    def call
      Rails.logger.debug '[INFO] Starting Factor Score Engine'
      load_instruments
      analyze_all
      export_results
      Rails.logger.debug { "[INFO] Factor scoring complete. CSV saved to #{OUTPUT_CSV}" }
    end

    private

    def load_instruments
      Rails.logger.debug '[INFO] Loading instruments from database'
      @symbols = Instrument.where(exchange: 'NSE', segment: 'E', instrument: 'EQUITY')
                           .select(:security_id, :symbol_name)
                           .distinct
                           .limit(500)
                           .map { |i| { security_id: i.security_id, symbol: i.symbol_name } }
      Rails.logger.debug { "[INFO] Loaded #{@symbols.size} instruments" }
    end

    def analyze_all
      @results = []
      @symbols.each_with_index do |stock, index|
        sleep(1.0 / RATE_LIMIT) # Enforce API rate limit

        Rails.logger.debug { "[DEBUG] Analyzing: #{stock[:symbol]} (#{index + 1}/#{@symbols.size})" }
        historical = begin
          Dhanhq::API::Historical.daily({
                                          securityId: stock[:security_id],
                                          exchangeSegment: 'NSE_EQ',
                                          instrument: 'EQUITY',
                                          fromDate: 1.year.ago.strftime('%Y-%m-%d'),
                                          toDate: Time.zone.today.strftime('%Y-%m-%d')
                                        })
        rescue StandardError => e
          Rails.logger.debug { "[WARN] Failed to fetch historical data for #{stock[:symbol]}: #{e.message}" }
          nil
        end

        prices = historical&.dig('close')&.map(&:to_f) || []
        volumes = historical&.dig('volume')&.map(&:to_i) || []

        score = compute_score(prices, volumes)
        Rails.logger.debug { "[DEBUG] Score for #{stock[:symbol]}: #{score[:score]}" }

        @results << stock.merge(score) if (score[:score]).positive?
      end
    end

    def compute_score(prices, volumes)
      price_momentum = prices.any? ? ((prices.last - prices.first) / prices.first * 100).round(2) : 0
      volatility = prices.any? ? (prices.max - prices.min).round(2) : 0
      volume_trend = volumes.any? ? ((volumes.last - volumes.first) / volumes.first.to_f * 100).round(2) : 0
      moving_average_trend = prices.length >= 200 ? (prices.last - (prices[-200..].sum / 200.0)).round(2) : 0
      atr_volatility = compute_atr(prices)

      {
        price_momentum: price_momentum,
        volatility: volatility,
        volume_trend: volume_trend,
        moving_average_trend: moving_average_trend,
        atr_volatility: atr_volatility,
        score: (
          score_momentum(price_momentum) +
          score_volatility(volatility) +
          score_volume(volume_trend) +
          score_ma(moving_average_trend) +
          score_atr(atr_volatility)
        )
      }
    end

    def compute_atr(prices, period = 14)
      return 0 if prices.length < period + 1

      trs = (1...prices.length).map do |i|
        (prices[i] - prices[i - 1]).abs
      end
      atr = trs.last(period).sum / period.to_f
      atr.round(2)
    end

    def score_momentum(val)
      if val > 20
        2
      else
        val > 10 ? 1 : 0
      end
    end

    def score_volatility(val)
      if val > 100
        2
      else
        val > 50 ? 1 : 0
      end
    end

    def score_volume(val)
      if val > 20
        2
      else
        val > 5 ? 1 : 0
      end
    end

    def score_ma(val)
      if val > 20
        2
      else
        val > 10 ? 1 : 0
      end
    end

    def score_atr(val)
      if val > 20
        2
      else
        val > 10 ? 1 : 0
      end
    end

    def export_results
      sorted = @results.sort_by { |s| -s[:score] }
      CSV.open(OUTPUT_CSV, 'w') do |csv|
        csv << %w[symbol security_id price_momentum volatility volume_trend moving_average_trend atr_volatility score]
        sorted.each do |r|
          csv << [
            r[:symbol], r[:security_id], r[:price_momentum], r[:volatility],
            r[:volume_trend], r[:moving_average_trend], r[:atr_volatility], r[:score]
          ]
        end
      end

      Rails.logger.debug { "[INFO] Catalog scoring completed. CSV exported to #{OUTPUT_CSV}" }
    end
  end
end
