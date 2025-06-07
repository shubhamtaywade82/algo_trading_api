module Openai
  class Client
    def self.[] # syntactic sugar → Openai::Client[:chat]
      instance
    end

    def self.instance
      @instance ||= ::OpenAI::Client.new # picks global config
    end
  end
end