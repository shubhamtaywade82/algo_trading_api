# frozen_string_literal: true

module Openai
  class ChatRouter
    LIGHT   = 'gpt-3.5-turbo-0125'
    HEAVY   = 'gpt-4o'
    TOKENS_LIMIT = 2_000 # ≈ words * 1.5

    # High-level helper – returns plain text
    # ------------------------------------------------------------
    def self.ask!(user_prompt,
                  system: default_system,
                  model:  nil,
                  temperature: 0.7)
      mdl = model || choose_model(user_prompt)

      resp = Client.instance.chat(
        parameters: {
          model: mdl,
          messages: [
            { role: 'system', content: system },
            { role: 'user',   content: user_prompt }
          ],
          temperature: temperature
        }
      )

      resp.dig('choices', 0, 'message', 'content').to_s.strip
    end

    # ------------------------------------------------------------
    private_class_method def self.choose_model(prompt)
      tokens = OpenAI.rough_token_count(prompt.to_s)
      tokens > TOKENS_LIMIT ? HEAVY : LIGHT
    end

    private_class_method def self.default_system
      'You are a helpful assistant specialised in Indian equity & derivatives.'
    end
  end
end
