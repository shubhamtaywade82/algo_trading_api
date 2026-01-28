# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe LevelsUpdateJob do
  describe '#perform' do
    it 'invokes the levels:update rake task' do
      expect(Rake::Task).to receive(:[]).with('levels:update').and_return(double(invoke: true))

      described_class.perform_now
    end

    it 'runs without errors' do
      allow(Rake::Task).to receive(:[]).with('levels:update').and_return(double(invoke: true))

      expect { described_class.perform_now }.not_to raise_error
    end
  end
end
