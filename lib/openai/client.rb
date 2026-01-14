module Openai
  class Client
    # syntactic sugar → Openai::Client[:chat]
    def self.[]
      instance
    end

    def self.instance
      unless defined?(::OpenAI::Client)
        raise 'OpenAI client is not available. Set LLM_PROVIDER=openai or add/configure the OpenAI gem.'
      end

      @instance ||= ::OpenAI::Client.new # picks global config
    end
  end
end