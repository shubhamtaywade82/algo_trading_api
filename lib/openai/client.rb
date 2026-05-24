# frozen_string_literal: true

module Openai
  class Client
    def self.instance
      @instance ||= new
    end

    def chat(parameters:)
      if Openai::Backend.official?
        chat_official(parameters)
      else
        chat_community(parameters)
      end
    end

    private

    # OFFICIAL SDK (Responses API)
    # Accepts chat-like parameters ({ model:, messages:, temperature:, max_tokens:, ... })
    # and adapts them to Responses API.
    def chat_official(parameters)
      client       = ::OpenAI::Client.new(api_key: ENV.fetch('OPENAI_API_KEY', nil)) # official gem; reads ENV["OPENAI_API_KEY"]
      model        = parameters[:model]
      messages     = parameters[:messages] || []
      temperature  = parameters[:temperature]
      max_tokens   = parameters[:max_tokens]
      resp_format  = parameters[:response_format]
      tools        = parameters[:tools]
      tool_choice  = parameters[:tool_choice]

      input = messages.map do |m|
        role    = m[:role] || m['role'] || 'user'
        content = m[:content] || m['content']

        items = case content
                when String then [{ type: 'input_text', text: content }]
                when Array  then content.map { |c| map_content_item_to_responses(c) }
                when Hash   then [map_content_item_to_responses(content)]
                else             [{ type: 'input_text', text: content.to_s }]
                end

        { role: role, content: items }
      end

      params = {
        model: model,
        input: input,
        temperature: temperature
      }
      params[:max_output_tokens] = max_tokens if max_tokens
      params[:response_format]   = normalize_responses_response_format(resp_format) if resp_format
      if tools
        ttools, tchoice = normalize_responses_tools(tools, tool_choice)
        params[:tools]       = ttools if ttools
        params[:tool_choice] = tchoice if tchoice
      end

      # IMPORTANT: Responses API expects everything under `parameters:`
      resp = client.responses.create(parameters: params)
      content = (resp['output_text'] || '').to_s

      # Normalize to a Chat-Completions-like shape
      { 'choices' => [{ 'message' => { 'content' => content } }] }
    end

    # COMMUNITY SDK (ruby-openai) — unchanged
    def chat_community(parameters)
      client = ::OpenAI::Client.new(access_token: ENV.fetch('OPENAI_API_KEY'))
      client.chat(parameters: parameters) # returns {"choices"=>...}
    end

    # ------- helpers for official Responses API -------
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
      when Hash then format
      end
    end

    def normalize_responses_tools(tools, tool_choice)
      norm = tools.map do |t|
        if t.is_a?(Hash) && (t[:type] == 'function' || t['type'] == 'function')
          t
        else
          { type: 'function',
            function: t[:function] || t['function'] || t }
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
  end
end