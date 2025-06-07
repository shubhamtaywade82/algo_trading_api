module Openai
  class ChatRouter
    # Adaptive model selection based on prompt length / complexity
    def self.route(prompt:, system: nil, model: nil)
      selected_model = model || choose_model(prompt)
      Rails.logger.info("[OpenAI] Using model: #{selected_model}")

      Client.instance.chat(
        parameters: {
          model: selected_model,
          messages: build_messages(prompt, system),
          temperature: 0.7
        }
      )
    end

    def self.choose_model(prompt)
      word_count = prompt.to_s.split.size
      return 'gpt-4o' if word_count > 400
      return 'gpt-4' if word_count > 150

      'gpt-3.5-turbo'
    end

    def self.build_messages(prompt, system)
      system_msg = system || 'You are a helpful assistant for financial portfolio analysis and trading.'
      [
        { role: 'system', content: system_msg },
        { role: 'user', content: prompt }
      ]
    end
  end
end