# frozen_string_literal: true

module Openai
  class ChatRouter
    LIGHT        = ENV.fetch('OPENAI_LIGHT_MODEL',  'gpt-4o-mini')
    HEAVY        = ENV.fetch('OPENAI_HEAVY_MODEL',  'gpt-5')
    TOKENS_LIMIT = (ENV['OPENAI_TOKEN_SWITCH'] || 200).to_i

    class << self
      # One method to rule them all.
      #
      # Usage:
      #   text = Openai::ChatRouter.ask!(
      #     "User prompt",
      #     system: "System seed",
      #     temperature: 0.3,
      #     max_tokens: 800,
      #     response_format: :json_object,     # or { type: "json_schema", json_schema: {...} } for official
      #     tools: [...], tool_choice: "auto",
      #     stream: proc { |delta| print delta }  # optional streaming
      #   )
      #
      def ask!(user_prompt,
               system: default_system,
               model: nil,
               temperature: 0.7,
               max_tokens: nil,
               force: false,
               response_format: nil,
               tools: nil,
               tool_choice: nil,
               stream: nil,
               messages: nil, # optional prebuilt messages (chat-completions style)
               retries: 3,
               backoff: 3,
               **_extra)
        mdl = resolve_model(model, force, "#{system} #{user_prompt} #{messages}")

        # Build a chat-style messages array that both SDKs can understand (directly or via adapter).
        chat_messages = build_chat_messages(system, user_prompt, messages)

        if stream
          if Backend.official?
            return stream_official(mdl, chat_messages, temperature, max_tokens, response_format, tools, tool_choice,
                                   stream)
          end

          return stream_community(mdl, chat_messages, temperature, max_tokens, response_format, tools, tool_choice, stream)
        end

        # Non-streaming → use your Client wrapper to keep one source of truth.
        params = {
          model: mdl,
          messages: chat_messages,
          temperature: temperature
        }
        params[:max_tokens]      = max_tokens if max_tokens
        params[:response_format] = normalize_chat_response_format(response_format) if response_format
        params[:tools]           = tools if tools
        params[:tool_choice]     = tool_choice if tool_choice

        attempt = 0
        begin
          resp = Openai::Client.instance.chat(parameters: params)
          extract_chat_text(resp)
        rescue StandardError => e
          attempt += 1
          raise if attempt > retries

          sleep(backoff * attempt)
          retry
        end
      end

      # ───────────────────────────────────────────────────────────
      # Streaming — Official SDK (Responses API)
      # ───────────────────────────────────────────────────────────
      def stream_official(model, chat_messages, temperature, max_tokens, response_format, tools, tool_choice, on_delta)
        client = ::OpenAI::Client.new(api_key: ENV.fetch('OPENAI_API_KEY', nil)) # official gem; reads ENV["OPENAI_API_KEY"]

        params = {
          model: model,
          input: build_responses_input_from_chat(chat_messages),
          temperature: temperature
        }
        params[:max_output_tokens] = max_tokens if max_tokens

        rf = normalize_responses_response_format(response_format)
        params[:response_format] = rf if rf

        if tools
          tt, tc = normalize_responses_tools(tools, tool_choice)
          params[:tools]       = tt if tt
          params[:tool_choice] = tc if tc
        end

        buffer = +''
        if client.responses.respond_to?(:stream)
          client.responses.stream(parameters: params) do |event|
            # Newer SDK emits structured events
            if event['type'] == 'response.output_text.delta'
              delta = event['delta'].to_s
              on_delta.call(delta) if on_delta
              buffer << delta
            end
          end
        else
          # Older SDKs may accept a stream: proc
          client.responses.create(parameters: params.merge(stream: proc { |event|
            if event['type'] == 'response.output_text.delta'
              delta = event['delta'].to_s
              on_delta.call(delta) if on_delta
              buffer << delta
            end
          }))
        end
        buffer.strip
      end

      # ───────────────────────────────────────────────────────────
      # Streaming — Community SDK (Chat Completions)
      # ───────────────────────────────────────────────────────────
      def stream_community(model, chat_messages, temperature, max_tokens, _response_format, tools, tool_choice, on_delta)
        client = ::OpenAI::Client.new(access_token: ENV.fetch('OPENAI_API_KEY'))

        params = {
          model: model,
          messages: chat_messages,
          temperature: temperature
        }
        params[:max_tokens]  = max_tokens if max_tokens
        params[:tools]       = tools if tools
        params[:tool_choice] = tool_choice if tool_choice

        buffer = +''
        client.chat(parameters: params.merge(stream: proc { |chunk|
          delta = chunk.dig('choices', 0, 'delta', 'content').to_s
          unless delta.empty?
            on_delta.call(delta) if on_delta
            buffer << delta
          end
        }))
        buffer.strip
      end

      # ───────────────────────────────────────────────────────────
      # Helpers (shared)
      # ───────────────────────────────────────────────────────────
      def build_chat_messages(system, user_prompt, msgs)
        out = []
        out << { role: 'system', content: system } if system.present?
        if msgs&.any?
          out.concat(msgs) # caller provided Chat-Completions style
        else
          out << { role: 'user', content: user_prompt.to_s }
        end
        out
      end

      # Convert Chat-Completions style messages to Responses API input
      def build_responses_input_from_chat(messages)
        messages.map do |m|
          role    = m[:role] || m['role'] || 'user'
          content = m[:content] || m['content']

          items =
            case content
            when String
              [{ type: 'input_text', text: content }]
            when Array
              content.map { |it| map_content_item_to_responses(it) }
            when Hash
              [map_content_item_to_responses(content)]
            else
              [{ type: 'input_text', text: content.to_s }]
            end

          { role: role, content: items }
        end
      end

      def map_content_item_to_responses(item)
        return({ type: 'input_text', text: item.to_s }) unless item.is_a?(Hash)

        t = item[:type] || item['type']
        case t
        when 'input_text'  then item
        when 'input_image' then item
        when 'text'        then { type: 'input_text', text: item[:text] || item['text'] || item[:content] || item['content'] }
        when 'image_url'
          url = item.dig(:image_url, :url) || item.dig('image_url', 'url') || item[:url] || item['url']
          { type: 'input_image', image_url: url }
        else
          { type: 'input_text', text: item[:text] || item['text'] || item[:content].to_s }
        end
      end

      def normalize_responses_response_format(format)
        case format
        when :json_object, 'json_object' then { type: 'json_object' }
        when Hash then format # allow json_schema etc.
        end
      end

      def normalize_chat_response_format(format)
        case format
        when :json_object, 'json_object' then { type: 'json_object' }
        when Hash then format
        end
      end

      def normalize_responses_tools(tools, tool_choice)
        norm = tools.map do |t|
          if t.is_a?(Hash) && (t[:type] == 'function' || t['type'] == 'function')
            t
          else
            { type: 'function', function: t[:function] || t['function'] || t }
          end
        end

        choice =
          case tool_choice
          when nil, false            then nil
          when 'auto', :auto         then({ type: 'auto' })
          when 'none', :none         then({ type: 'none' })
          when Hash                  then tool_choice
          else { type: 'tool', tool_name: tool_choice.to_s }
          end

        [norm, choice]
      end

      def extract_chat_text(resp)
        # Normalize both SDK outputs (we already normalize in Client for non-streaming)
        resp.dig('choices', 0, 'message', 'content').to_s.strip
      end

      # — model selection
      def resolve_model(explicit_model, force, text)
        return HEAVY if force
        return explicit_model if explicit_model.present?

        token_estimate(text) > TOKENS_LIMIT ? HEAVY : LIGHT
      end

      def token_estimate(str)
        (str.to_s.length / 4.0).ceil # rough heuristic
      end

      def default_system
        'You are a helpful assistant specialised in Indian equities & derivatives.'
      end
    end
  end
end