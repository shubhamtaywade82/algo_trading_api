module Openai
  class MessageProcessor < ApplicationService
    def initialize(prompt, model: nil, system: nil)
      @prompt = prompt
      @model = model
      @system = system
    end

    def call
      text = ChatRouter.ask!(
        @prompt,
        model: @model,
        system: @system.presence || Openai::ChatRouter.send(:default_system)
      )
      log_info("OpenAI Response: #{text}")
      text
    rescue StandardError => e
      log_error("OpenAI call failed: #{e.class} - #{e.message}")
      nil
    end
  end
end