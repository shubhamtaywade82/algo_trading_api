# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  before_perform :ensure_dhan_token!

  # ActiveJob dispatches rescue handlers last-registered-first, so the order of
  # the two declarations below is the behaviour, not decoration.
  #
  # A blanket `rescue_from(StandardError)` used to sit after `retry_on`, which
  # made it the first handler matched: it logged and re-raised, and `retry_on`
  # never ran at all. No job in this app has ever retried. `retry_on` is now
  # declared first so it stays the fallback, and the deterministic failures
  # below are declared after so they are matched ahead of it.
  #
  # `wait:` is `:polynomially_longer`. Rails 8 removed `:exponentially_longer`,
  # which the old declaration still asked for — the first retry to be scheduled
  # would have raised `Couldn't determine a delay based on
  # :exponentially_longer` from inside the retry machinery. That never fired
  # only because the shadowing above meant no retry was ever scheduled.
  retry_on StandardError, attempts: 5, wait: :polynomially_longer do |job, error|
    ErrorLogger.log_error("#{job.class} gave up after #{job.executions} attempts", error)
    raise error
  end

  # A missing credential, a constant that does not resolve, a record the
  # database rejects: each fails identically on every attempt, so retrying one
  # buys four more copies of the same backtrace and nothing else. These are
  # logged once and dropped — whatever enqueued the work comes back on its own
  # once the underlying setting is fixed.
  discard_on KeyError, NameError, ActiveRecord::RecordInvalid do |job, error|
    ErrorLogger.log_error("#{job.class} failed on a condition no retry can fix", error)
  end

  private

  def ensure_dhan_token!
    Dhan::TokenManager.current_token!
  rescue StandardError => e
    Rails.logger.error("[DHAN] Token ensure failed: #{e.class} - #{e.message}")
    raise
  end
end
