require 'rails_helper'

RSpec.describe Openai::MessageProcessor, type: :service do
  describe '#call' do
    it 'delegates to Openai::ChatRouter.ask!' do
      allow(Openai::ChatRouter).to receive(:ask!).and_return('ok')

      out = described_class.call('hello', model: 'gpt-5-mini', system: 'sys')

      expect(Openai::ChatRouter).to have_received(:ask!).with('hello', model: 'gpt-5-mini', system: 'sys')
      expect(out).to eq('ok')
    end
  end
end

