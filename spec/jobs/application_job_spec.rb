# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationJob do
  # The adapter is set explicitly rather than inherited: these examples assert
  # on what a failure *enqueues*, which only the test adapter records.
  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
    ActiveJob::Base.queue_adapter = original
  end

  before do
    # The token check is a before_perform on every job; these examples are
    # about what happens once perform has failed.
    allow(Dhan::TokenManager).to receive(:current_token!).and_return('token')
    allow(ErrorLogger).to receive(:log_error)

    stub_const('FailingProbeJob', Class.new(described_class) do
      cattr_accessor :error_class, default: RuntimeError

      def perform
        raise self.class.error_class, 'probe failure'
      end
    end)
  end

  def enqueued_retries
    ActiveJob::Base.queue_adapter.enqueued_jobs.size
  end

  describe 'a transient failure' do
    before { FailingProbeJob.error_class = RuntimeError }

    it 'is retried' do
      expect { FailingProbeJob.perform_now }.to change { enqueued_retries }.by(1)
    end
  end

  # retry_on used to be shadowed by a blanket rescue_from declared after it,
  # and asked for :exponentially_longer, which Rails 8 removed. Either one on
  # its own is enough to stop a job ever retrying, so assert the delay is a
  # real one rather than only that something was enqueued.
  describe 'the retry delay' do
    it 'is one Rails 8 can compute' do
      expect { FailingProbeJob.perform_now }.not_to raise_error
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.first[:at]).to be_present
    end
  end

  describe 'a failure no retry can fix' do
    [KeyError, NameError, Dhan::TokenManager::MissingCredentialsError].each do |error_class|
      context "when the job raises #{error_class}" do
        before { FailingProbeJob.error_class = error_class }

        it 'is discarded rather than retried' do
          expect { FailingProbeJob.perform_now }.not_to(change { enqueued_retries })
        end

        it 'is logged once' do
          FailingProbeJob.perform_now

          expect(ErrorLogger).to have_received(:log_error).once
        end
      end
    end
  end
end
