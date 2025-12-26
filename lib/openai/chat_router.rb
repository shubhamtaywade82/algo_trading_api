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

      TelegramNotifier.send_chat_action(chat_id: nil, action: 'typing')
      resp = responses_create!(
        model: mdl,
        instructions: system,
        input: [{ role: 'user', content: user_prompt }],
        max_output_tokens: max_tokens
      )
      TelegramNotifier.send_chat_action(chat_id: nil, action: 'typing')
      extract_text(resp)
    end

    # Lower-level helper for the OpenAI Responses API.
    #
    # @param model [String]
    # @param instructions [String] (system prompt)
    # @param input [Array<Hash>] messages array in Responses API format
    # @param tools [Array<Hash>, nil] tool definitions (function/custom tools)
    # @param tool_choice [Object, String, nil]
    # @param parallel_tool_calls [Boolean, nil]
    # @param max_output_tokens [Integer, nil]
    # @return [Hash] raw Responses API payload
    def self.respond!(model:,
                      instructions:,
                      input:,
                      tools: nil,
                      tool_choice: nil,
                      parallel_tool_calls: nil,
                      max_output_tokens: nil)
      responses_create!(
        model: model,
        instructions: instructions,
        input: input,
        tools: tools,
        tool_choice: tool_choice,
        parallel_tool_calls: parallel_tool_calls,
        max_output_tokens: max_output_tokens
      )
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

    # =========================================================
    # Responses API internals
    # =========================================================
    def self.responses_create!(model:, instructions:, input:, tools: nil, tool_choice: nil, parallel_tool_calls: nil,
                               max_output_tokens: nil)
      params = {
        model: model,
        instructions: instructions,
        input: input
      }
      params[:tools] = tools if tools.present?
      params[:tool_choice] = tool_choice if tool_choice.present?
      params[:parallel_tool_calls] = parallel_tool_calls unless parallel_tool_calls.nil?
      params[:max_output_tokens] = max_output_tokens if max_output_tokens.present?

      client = Client.instance

      # Prefer Responses API; fall back to chat completions if gem/client doesn't support it.
      if client.respond_to?(:responses)
        api = client.responses
        return api.create(parameters: params) if api.respond_to?(:create)
      end

      # Legacy fallback (Chat Completions) to avoid hard crashes in older environments.
      legacy = {
        model: model,
        messages: [
          { role: 'system', content: instructions },
          { role: 'user', content: input.is_a?(Array) ? input.last&.[](:content) : input.to_s }
        ]
      }
      legacy[:max_tokens] = max_output_tokens if max_output_tokens.present?
      client.chat(parameters: legacy)
    end
    private_class_method :responses_create!

    def self.extract_text(resp)
      # 1) Responses API: some SDKs expose an output_text field.
      txt = resp.is_a?(Hash) ? (resp['output_text'] || resp[:output_text]) : nil
      return txt.to_s.strip if txt.present?

      # 2) Responses API: parse output items.
      if resp.is_a?(Hash) && resp['output'].is_a?(Array)
        parts = []
        resp['output'].each do |item|
          next unless item.is_a?(Hash)
          next unless item['type'] == 'message'

          content = item['content']
          next unless content.is_a?(Array)

          content.each do |c|
            next unless c.is_a?(Hash)
            # Typical: { "type": "output_text", "text": "..." }
            parts << c['text'] if c['text'].present?
          end
        end
        return parts.join("\n").strip if parts.any?
      end

      # 3) Chat Completions fallback shape.
      resp.dig('choices', 0, 'message', 'content').to_s.strip
    end
    private_class_method :extract_text
  end
end
