# frozen_string_literal: true

module Openai
  class ChatRouter
    LIGHT   = 'gpt-4o'
    HEAVY   = 'gpt-5-mini'
    TOKENS_LIMIT = 300 # ≈ words * 1.5

    # High-level helper – returns plain text
    # ------------------------------------------------------------
    def self.ask!(user_prompt,
                  system: default_system,
                  model:  nil,
                  max_tokens: nil,
                  force: false)
      mdl = resolve_model(model, force, "#{system} #{user_prompt}")

      pp mdl
      params = {
        model: mdl,
        messages: [
          { role: 'system', content: system },
          { role: 'user',   content: user_prompt }
        ]
      }
      params[:max_tokens] = max_tokens if max_tokens
      TelegramNotifier.send_chat_action(chat_id: nil, action: 'typing')
      resp = Client.instance.chat(parameters: params)
      TelegramNotifier.send_chat_action(chat_id: nil, action: 'typing')
      resp.dig('choices', 0, 'message', 'content').to_s.strip
    end

    # # ------------------------------------------------------------------
    # private_class_method :choose_model, :token_estimate, :default_system

    def self.choose_model(text)
      token_estimate(text) > TOKENS_LIMIT ? HEAVY : LIGHT
    end

    # =========================================================
    # Helpers
    # =========================================================
    def self.resolve_model(explicit_model, force, text)
      return HEAVY if force
      return explicit_model if explicit_model.present?

      # Environment-based default
      env_default = Rails.env.production? ? HEAVY : LIGHT

      # If you later want token-based switching, uncomment:
      if Rails.env.production?
        token_estimate(text) > TOKENS_LIMIT ? HEAVY : env_default
      else
        env_default
      end
    end
    private_class_method :resolve_model

    # Very light-weight fallback when tiktoken isn't installed.
    # A token ≈ 4 characters for English-ish text.
    # very rough: 1 token ≈ 4 characters
    def self.token_estimate(str)
      (str.to_s.length / 4.0).ceil
    end
    private_class_method :token_estimate

    def self.default_system
      'You are a helpful assistant specialised in Indian equities & derivatives.'
    end
  end
end
