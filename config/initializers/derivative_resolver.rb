# frozen_string_literal: true

# Pre-load the Dhan scrip master index into memory for fast derivative resolution.
# This uses ~200MB of RAM for ~400k rows, but ensures deterministic 1ms lookups.
# Requires tmp/dhan_scrip_master.csv to be present (imported via bin/rails import:instruments).

Rails.application.config.after_initialize do
  # We run this in a background thread to not block boot, but it's safe because
  # DerivativeResolver.call will wait/load it if called before it's ready.
  Thread.new do
    begin
      Trading::DerivativeResolver.load_index!
    rescue => e
      Rails.logger.error "Failed to load Trading::DerivativeResolver index: #{e.message}"
    end
  end
end
