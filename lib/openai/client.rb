module Openai
  class Client
    # syntactic sugar → Openai::Client[:chat]
    def self.[]
      instance
    end

    def self.instance
      @instance ||= ::OpenAI::Client.new # picks global config
    end
  end
end