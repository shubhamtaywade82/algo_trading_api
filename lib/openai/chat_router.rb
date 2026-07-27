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
      return ask_ollama_cloud!(user_prompt, system: system, model: model) if ollama_cloud?

      ask_openai!(user_prompt, system: system, model: model, max_tokens: max_tokens, force: force)
    end

    def self.ask_openai!(user_prompt, system:, model: nil, max_tokens: nil, force: false)
      mdl = resolve_model(model, force, "#{system} #{user_prompt}")
      # Not `backend_label`: on the fallback path that would claim Ollama Cloud
      # while OpenAI is actually serving the request.
      Rails.logger.info "[Openai] #{openai_backend_label(mdl)}"
      TelegramNotifier.send_chat_action(chat_id: nil, action: 'typing')

      chat = RubyLLM.chat(model: mdl, provider: :openai, assume_model_exists: true)
      chat.with_instructions(system) if system.present?
      chat.with_params(max_tokens: max_tokens) if max_tokens.present?

      response = chat.ask(user_prompt)
      TelegramNotifier.send_chat_action(chat_id: nil, action: 'typing')
      response.content.to_s.strip
    end

    # Ollama Cloud, through the rotating key pool.
    #
    # Every existing caller — the screener, the portfolio and position
    # analysers, the market commentary — reaches this class rather than a
    # client, so switching backend is an env change rather than a code change.
    # If the keys are missing the flag is ignored and OpenAI still serves the
    # request, so a half-finished rollout cannot take the AI layer down.
    def self.ask_ollama_cloud!(user_prompt, system:, model: nil)
      Rails.logger.info "[Openai] #{backend_label(model)}"
      TelegramNotifier.send_chat_action(chat_id: nil, action: 'typing')
      Llm::KeyRotator.ask(user_prompt, system: system, model: model).strip
    rescue Llm::KeyRotator::Error => e
      Rails.logger.error("[Openai] Ollama Cloud unavailable, falling back to OpenAI: #{e.message}")
      ask_openai!(user_prompt, system: system, model: model)
    end

    # @return [Boolean] whether Ollama Cloud should serve chat requests
    def self.ollama_cloud?
      ENV['LLM_BACKEND'].to_s.casecmp('ollama_cloud').zero? && Llm::KeyRotator.configured?
    end

    # Public: so callers can show which backend will be used (e.g. in Telegram).
    def self.backend_label(resolved_model = nil)
      return "Ollama Cloud (#{resolved_model || Llm::KeyRotator.default_model})" if ollama_cloud?

      openai_backend_label(resolved_model)
    end

    def self.openai_backend_label(resolved_model = nil)
      if using_ollama?
        "Ollama (#{resolved_model || ollama_model_from_env})"
      else
        "OpenAI (#{resolved_model || LIGHT})"
      end
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
      ENV['OPENAI_OLLAMA_MODEL'].presence || ENV['OLLAMA_MODEL'].presence || 'qwen3:latest'
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