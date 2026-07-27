# frozen_string_literal: true

# One row per scrip-master import, replacing the loose `app_settings` strings
# the importer used to write. Keeps history, records failures, and makes
# "is the instrument master stale?" a query rather than a string comparison.
class InstrumentSyncRun < ApplicationRecord
  STALE_AFTER = 24.hours

  enum :status, { running: 'running', succeeded: 'succeeded', failed: 'failed' }, prefix: true
  enum :source, { url: 'url', file: 'file', inline: 'inline' }, prefix: true

  validates :started_at, presence: true

  scope :recent, -> { order(started_at: :desc) }

  def self.last_success
    status_succeeded.recent.first
  end

  # True when no import has succeeded inside STALE_AFTER. Callers that size
  # positions off `lot_size` or resolve expiries should refuse rather than
  # trade against a master that may predate an expiry roll.
  def self.stale?
    run = last_success
    run.nil? || run.finished_at.nil? || run.finished_at < STALE_AFTER.ago
  end

  def duration
    return nil unless started_at && finished_at

    finished_at - started_at
  end

  def succeed!(**counts)
    update!(counts.merge(status: 'succeeded', finished_at: Time.current))
  end

  def fail!(error)
    update!(status: 'failed', finished_at: Time.current, error_message: error.to_s.truncate(2_000))
  end
end
