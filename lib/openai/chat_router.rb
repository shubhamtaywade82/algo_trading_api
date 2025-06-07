module Openai
  class ChatRouter
    LIGHT  = 'gpt-3.5-turbo-0125'
    HEAVY  = 'gpt-4o'                    # fall back to 'gpt-4-turbo' if needed
    LIMIT  = 2_000                       # rough tokens (≈ words*1.5)

    class << self
      def ask!(user_prompt, system: default_system, model: nil, temperature: 0.7)
        mdl  = model || choose_model(user_prompt)
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

      private

      def choose_model(prompt)
        tokens = OpenAI.rough_token_count(prompt.to_s)
        tokens > LIMIT ? HEAVY : LIGHT
      end

      def default_system
        'You are a helpful assistant specialised in Indian equity & derivatives.'
      end
    end
  end
end