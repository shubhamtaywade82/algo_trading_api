module Openai
  class Client
    # syntactic sugar → Openai::Client[:chat]
    def self.[]
      instance
    end

    def self.instance
      raise 'OpenAI client is not available. Set LLM_PROVIDER=openai or add/configure the OpenAI gem.' unless defined?(::OpenAI::Client)

      @instance ||= ::OpenAI::Client.new # picks global config
    end
  end
end