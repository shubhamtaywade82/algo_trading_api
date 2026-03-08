# frozen_string_literal: true

require 'open-uri'

module InstrumentsImport
  # Handles fetching and caching the scrip master CSV from DhanHQ.
  class Fetcher < ApplicationService
    CSV_URL       = 'https://images.dhan.co/api-data/api-scrip-master-detailed.csv'
    CACHE_PATH    = Rails.root.join('tmp/dhan_scrip_master.csv')
    CACHE_MAX_AGE = 24.hours

    def initialize(file_path: nil)
      @file_path = file_path
    end

    def call
      return File.read(@file_path) if @file_path

      fetch_with_cache
    end

    private

    def fetch_with_cache
      return CACHE_PATH.read if CACHE_PATH.exist? && (Time.current - CACHE_PATH.mtime) < CACHE_MAX_AGE

      csv_text = URI.open(CSV_URL, &:read)
      CACHE_PATH.dirname.mkpath
      File.write(CACHE_PATH, csv_text)
      csv_text
    rescue StandardError => e
      raise e unless CACHE_PATH.exist?

      CACHE_PATH.read
    end
  end
end
