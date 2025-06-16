# frozen_string_literal: true

module Openai
  class ChatRouter
    LIGHT   = 'gpt-3.5-turbo-0125'
    HEAVY   = 'gpt-4o'
    TOKENS_LIMIT = 3_000 # ≈ words * 1.5

    # High-level helper – returns plain text
    # ------------------------------------------------------------
    def self.ask!(user_prompt,
                  system: default_system,
                  model:  nil,
                  temperature: 0.7,
                  max_tokens: nil,
                  force: false)
      mdl = model || choose_model("#{system} #{user_prompt}")
      mdl = HEAVY if force

      params = {
        model: mdl,
        messages: [
          { role: 'system', content: system },
          { role: 'user',   content: user_prompt }
        ],
        temperature: temperature
      }
      params[:max_tokens] = max_tokens if max_tokens

      resp = Client.instance.chat(parameters: params)
      resp.dig('choices', 0, 'message', 'content').to_s.strip
    end

    # # ------------------------------------------------------------------
    # private_class_method :choose_model, :token_estimate, :default_system

    def self.choose_model(text)
      token_estimate(text) > TOKENS_LIMIT ? HEAVY : LIGHT
    end

    # Very light-weight fallback when tiktoken isn't installed.
    # A token ≈ 4 characters for English-ish text.
    def self.token_estimate(str)
      (str.to_s.length / 4.0).ceil
    end

    def self.default_system
      'You are a helpful assistant specialised in Indian equities & derivatives.'
    end
  end
end
