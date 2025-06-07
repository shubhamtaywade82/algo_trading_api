module Openai
  class MessageProcessor < ApplicationService
    def initialize(prompt, model: nil, system: nil)
      @prompt = prompt
      @model = model
      @system = system
    end

    def call
      response = ChatRouter.route(prompt: @prompt, model: @model, system: @system)
      choices = response.dig('choices', 0, 'message', 'content')
      log_info("OpenAI Response: #{choices}")
      choices
    rescue StandardError => e
      log_error("OpenAI call failed: #{e.class} - #{e.message}")
      nil
    end
  end
end