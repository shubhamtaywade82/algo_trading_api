# frozen_string_literal: true

module Llm
  module Tools
    # Exposes an existing `AI::Tools::*` tool to a plain RubyLLM chat.
    #
    # The agent tools already wrap this app's DhanHQ access — option chains,
    # candles, funds, positions — with the retries, segment mapping and
    # analyser plumbing that took real work to get right. Re-implementing them
    # against a `RubyLLM::Tool` base would fork that logic and let the two
    # drift, which is how an AI layer ends up reasoning over stale data.
    #
    # `Agents::Tool` subclasses take a tool context as their first argument and
    # every tool in this app ignores it, so `nil` is passed through.
    class Base < RubyLLM::Tool
      class << self
        # Declares which agent tool this one delegates to.
        def delegates_to(agent_tool)
          @agent_tool = agent_tool
        end

        attr_reader :agent_tool
      end

      # RubyLLM derives a tool's name from its full class path, which would
      # present these to the model as `llm--tools--option_chain`. The model
      # selects tools by name and repeats it back in every call, so it gets the
      # short one.
      def name
        self.class.name.demodulize.underscore
      end

      def execute(**args)
        tool = self.class.agent_tool
        raise NotImplementedError, "#{self.class} must declare `delegates_to`" unless tool

        tool.new.perform(nil, **args.symbolize_keys)
      rescue StandardError => e
        # Returned rather than raised: a tool failure is information the model
        # can act on ("the chain is unavailable, say so"), whereas an exception
        # aborts the whole turn.
        Rails.logger.error("[Llm::Tools] #{self.class.name} failed: #{e.class} - #{e.message}")
        { error: e.message }
      end
    end
  end
end
