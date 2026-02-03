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
      Rails.logger.info "[Openai] #{backend_label(mdl)}"
      params = {
        model: mdl,
        messages: [
          { role: 'system', content: system },
          { role: 'user',   content: user_prompt }
        ]
      }
      params[:max_completion_tokens] = max_tokens if max_tokens
      TelegramNotifier.send_chat_action(chat_id: nil, action: 'typing')
      resp = Client.instance.chat(parameters: params)
      TelegramNotifier.send_chat_action(chat_id: nil, action: 'typing')
      resp.dig('choices', 0, 'message', 'content').to_s.strip
    end

    # Public: so callers can show which backend will be used (e.g. in Telegram).
    def self.backend_label(resolved_model = nil)
      if using_ollama?
        "Ollama (#{resolved_model || ollama_model_from_env})"
      else
        "OpenAI (#{resolved_model || LIGHT})"
      end
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

      return ollama_model_from_env if using_ollama?

      env_default = Rails.env.production? ? HEAVY : LIGHT
      if Rails.env.production?
        token_estimate(text) > TOKENS_LIMIT ? HEAVY : env_default
      else
        env_default
      end
    end
    private_class_method :resolve_model

    def self.using_ollama?
      return false if Rails.env.production?

      base = ENV['OPENAI_URI_BASE'].to_s
      base.blank? || base.include?('11434')
    end
    private_class_method :using_ollama?

    # App-scoped first so .env overrides global OLLAMA_MODEL (e.g. Cursor/shell).
    def self.ollama_model_from_env
      ENV['OPENAI_OLLAMA_MODEL'].presence || ENV['OLLAMA_MODEL'].presence || 'llama3.1:8b-instruct-q4_K_M'
    end
    private_class_method :ollama_model_from_env

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
