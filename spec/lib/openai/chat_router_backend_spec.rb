# frozen_string_literal: true

require 'rails_helper'

# Six services reach the LLM through this class — the screener, the portfolio
# and position analysers, the market commentary. Switching them to Ollama Cloud
# has to be an env change, not six code changes.
RSpec.describe Openai::ChatRouter do
  before { allow(TelegramNotifier).to receive(:send_chat_action) }

  def with_env(vars)
    stub_const('ENV', ENV.to_h.merge(vars).compact)
  end

  describe '.ask!' do
    it 'routes to Ollama Cloud when the backend is selected and keys exist' do
      with_env('LLM_BACKEND' => 'ollama_cloud', 'OLLAMA_API_KEY_1' => 'key-one')
      allow(Llm::KeyRotator).to receive(:ask).and_return('  from ollama  ')

      expect(described_class.ask!('what is the pcr', system: 'be brief')).to eq('from ollama')
      expect(Llm::KeyRotator).to have_received(:ask).with('what is the pcr', system: 'be brief', model: nil)
    end

    # A half-finished rollout — the flag set before the keys are in place —
    # must not take the AI layer down.
    it 'stays on OpenAI when the flag is set but no key is configured' do
      with_env({ 'LLM_BACKEND' => 'ollama_cloud' }.merge((1..5).to_h { |i| ["OLLAMA_API_KEY_#{i}", nil] }))
      allow(Llm::KeyRotator).to receive(:ask)
      allow(described_class).to receive(:ask_openai!).and_return('from openai')

      expect(described_class.ask!('hello')).to eq('from openai')
      expect(Llm::KeyRotator).not_to have_received(:ask)
    end

    it 'ignores the key pool when the backend is not selected' do
      with_env('LLM_BACKEND' => nil, 'OLLAMA_API_KEY_1' => 'key-one')
      allow(Llm::KeyRotator).to receive(:ask)
      allow(described_class).to receive(:ask_openai!).and_return('from openai')

      expect(described_class.ask!('hello')).to eq('from openai')
      expect(Llm::KeyRotator).not_to have_received(:ask)
    end

    # Losing every key should degrade to the other provider, not to an
    # exception in the middle of a screener run.
    it 'falls back to OpenAI when every Ollama key is exhausted' do
      with_env('LLM_BACKEND' => 'ollama_cloud', 'OLLAMA_API_KEY_1' => 'key-one')
      allow(Llm::KeyRotator).to receive(:ask).and_raise(Llm::KeyRotator::Error, 'all keys quarantined')
      allow(described_class).to receive(:ask_openai!).and_return('from openai')

      expect(described_class.ask!('hello')).to eq('from openai')
    end
  end

  describe '.ask_openai!' do
    it 'invokes RubyLLM chat with provider :openai' do
      chat_double = instance_double(RubyLLM::Chat)
      response_double = double('response', content: ' response text ')

      allow(RubyLLM).to receive(:chat).with(model: 'gpt-4o', provider: :openai, assume_model_exists: true).and_return(chat_double)
      allow(chat_double).to receive(:with_instructions)
      allow(chat_double).to receive(:with_params)
      allow(chat_double).to receive(:ask).with('hello').and_return(response_double)

      res = described_class.ask_openai!('hello', system: 'sys prompt', model: 'gpt-4o', max_tokens: 100)
      expect(res).to eq('response text')
      expect(chat_double).to have_received(:with_instructions).with('sys prompt')
      expect(chat_double).to have_received(:with_params).with(max_tokens: 100)
    end
  end

  describe '.backend_label' do
    it 'names Ollama Cloud when it is serving' do
      with_env('LLM_BACKEND' => 'ollama_cloud', 'OLLAMA_API_KEY_1' => 'key-one',
               'OLLAMA_DEFAULT_MODEL' => 'qwen3:cloud')

      expect(described_class.backend_label).to eq('Ollama Cloud (qwen3:cloud)')
    end

    it 'names OpenAI otherwise' do
      with_env({ 'LLM_BACKEND' => nil, 'OPENAI_URI_BASE' => 'https://api.openai.com/v1' })

      expect(described_class.backend_label).to include('OpenAI')
    end
  end
end
