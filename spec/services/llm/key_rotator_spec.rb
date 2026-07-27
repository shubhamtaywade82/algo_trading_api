# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Llm::KeyRotator do
  let(:keys) { { 1 => 'key-one', 2 => 'key-two', 3 => 'key-three' } }

  before do
    described_class.reset!
    (1..described_class::MAX_KEYS).each do |index|
      stub_const('ENV', ENV.to_h.merge("OLLAMA_API_KEY_#{index}" => keys[index]).compact)
    end
  end

  after { described_class.reset! }

  describe '.with_key' do
    it 'uses the first configured key' do
      used = described_class.with_key { |_context, index| index }

      expect(used).to eq(1)
    end

    # The draft this replaces returned nil on success: a bare `return` after
    # the yield discarded the model's reply, so every caller got nothing.
    it 'returns the block value rather than swallowing it' do
      expect(described_class.with_key { |_c, _i| 'the answer' }).to eq('the answer')
    end

    it 'rotates to the next key when one is unauthorized' do
      attempts = []

      result = described_class.with_key do |_context, index|
        attempts << index
        raise RubyLLM::UnauthorizedError, 'revoked' if index == 1

        'served by two'
      end

      expect(attempts).to eq([1, 2])
      expect(result).to eq('served by two')
    end

    it 'rotates past a rate-limited key' do
      attempts = []

      described_class.with_key do |_context, index|
        attempts << index
        raise RubyLLM::RateLimitError, 'slow down' if index < 3

        'ok'
      end

      expect(attempts).to eq([1, 2, 3])
    end

    it 'keeps a failed key out of rotation while it is quarantined' do
      described_class.with_key do |_context, index|
        raise RubyLLM::ServerError, 'boom' if index == 1

        'ok'
      end

      expect(described_class.with_key { |_c, index| index }).to eq(2)
    end

    it 'lets the key back in once the quarantine lapses' do
      described_class.with_key do |_context, index|
        raise RubyLLM::ServerError, 'boom' if index == 1

        'ok'
      end

      travel_to(described_class::QUARANTINE.from_now + 1.second) do
        expect(described_class.with_key { |_c, index| index }).to eq(1)
      end
    end

    it 'raises once every key has failed' do
      expect do
        described_class.with_key { |_c, _i| raise RubyLLM::UnauthorizedError, 'nope' }
      end.to raise_error(described_class::Error, /last error/)
    end

    # A malformed request fails identically on all five keys. Rotating would
    # burn the whole pool over a caller-side bug.
    it 'does not rotate on an error that is the caller\'s fault' do
      attempts = []

      expect do
        described_class.with_key do |_context, index|
          attempts << index
          raise RubyLLM::BadRequestError, 'malformed tool call'
        end
      end.to raise_error(RubyLLM::BadRequestError)

      expect(attempts).to eq([1])
      expect(described_class.health.first[:state]).to eq('available')
    end

    it 'explains itself when no key is configured' do
      stub_const('ENV', ENV.to_h.except(*(1..5).map { |i| "OLLAMA_API_KEY_#{i}" }))

      expect { described_class.with_key { |_c, _i| 'unused' } }
        .to raise_error(described_class::Error, /no Ollama API keys configured/)
    end
  end

  describe '.with_key context isolation' do
    # The market-feed thread and web requests share this process; a global
    # RubyLLM.configure would swap the key underneath a concurrent caller.
    it 'binds the key to a context without touching global config' do
      before_key = RubyLLM.config.ollama_api_key

      described_class.with_key do |context, _index|
        expect(context.config.ollama_api_key).to eq('key-one')
        expect(context.config.ollama_api_base).to eq(described_class.api_base)
      end

      expect(RubyLLM.config.ollama_api_key).to eq(before_key)
    end
  end

  describe '.health' do
    it 'reports every slot without ever exposing a key' do
      health = described_class.health

      expect(health.size).to eq(described_class::MAX_KEYS)
      expect(health.pluck(:state))
        .to eq(['available', 'available', 'available', 'not configured', 'not configured'])
      expect(health.to_s).not_to include('key-one')
    end
  end

  describe '.configured?' do
    it 'is false with no keys' do
      stub_const('ENV', ENV.to_h.except(*(1..5).map { |i| "OLLAMA_API_KEY_#{i}" }))

      expect(described_class).not_to be_configured
    end

    it 'is true with at least one' do
      expect(described_class).to be_configured
    end
  end

  describe '.api_base' do
    # RubyLLM posts to {base}/chat/completions, so a base without /v1 makes
    # every request 404 against Ollama Cloud.
    it 'defaults to the OpenAI-compatible path' do
      stub_const('ENV', ENV.to_h.except('OLLAMA_API_BASE'))

      expect(described_class.api_base).to end_with('/v1')
    end
  end
end
