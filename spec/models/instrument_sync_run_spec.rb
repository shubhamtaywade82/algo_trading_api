# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstrumentSyncRun do
  def succeeded_at(time, **counts)
    described_class.create!(source: 'url', status: 'succeeded', started_at: time,
                            finished_at: time, **counts)
  end

  describe '.stale?' do
    it 'is stale when no import has ever succeeded' do
      expect(described_class).to be_stale
    end

    it 'is stale when the only success predates the window' do
      succeeded_at(described_class::STALE_AFTER.ago - 1.hour)

      expect(described_class).to be_stale
    end

    it 'is fresh after a recent success' do
      succeeded_at(1.hour.ago)

      expect(described_class).not_to be_stale
    end

    it 'ignores a failure newer than the last success' do
      succeeded_at(1.hour.ago)
      described_class.create!(source: 'url', status: 'failed', started_at: Time.current,
                              finished_at: Time.current, error_message: 'boom')

      expect(described_class).not_to be_stale
      expect(described_class.last_success.status).to eq('succeeded')
    end

    it 'is stale while a run is still in flight' do
      described_class.create!(source: 'url', status: 'running', started_at: Time.current)

      expect(described_class).to be_stale
    end
  end

  describe '#succeed!' do
    it 'records the counts and stamps the finish' do
      run = described_class.create!(source: 'url', status: 'running', started_at: 2.minutes.ago)

      run.succeed!(instrument_rows: 10, derivative_rows: 20, deactivated_rows: 3)

      expect(run).to have_attributes(status: 'succeeded', instrument_rows: 10,
                                     derivative_rows: 20, deactivated_rows: 3)
      expect(run.duration).to be > 0
    end
  end

  describe '#fail!' do
    it 'keeps the reason so a crashed import is distinguishable from one that never ran' do
      run = described_class.create!(source: 'url', status: 'running', started_at: Time.current)

      run.fail!('connection reset')

      expect(run).to have_attributes(status: 'failed', error_message: 'connection reset')
      expect(run.finished_at).to be_present
    end
  end
end
