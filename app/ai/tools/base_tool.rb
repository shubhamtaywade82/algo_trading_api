# frozen_string_literal: true

module AI
  module Tools
    # Abstract base class for all AI agent tools.
    #
    # Sub-classes implement:
    #   TOOL_NAME    = 'snake_case_name'
    #   DESCRIPTION  = 'What this tool does'
    #   PARAMETERS   = { type: 'object', properties: {...}, required: [...] }
    #
    #   def perform(args)  → serialisable result (Hash / Array / String)
    class BaseTool
      # Returns the OpenAI function-calling definition for this tool.
      def to_openai_definition
        {
          type: 'function',
          function: {
            name:        name,
            description: description,
            parameters:  parameters
          }
        }
      end

      def name
        self.class::TOOL_NAME
      end

      def description
        self.class::DESCRIPTION
      end

      def parameters
        self.class::PARAMETERS
      end

      # Sub-classes override this to do actual work.
      # @param args [Hash] parsed JSON arguments from LLM
      # @return [Hash|Array|String] serialisable result
      def perform(_args)
        raise NotImplementedError, "#{self.class.name}#perform not implemented"
      end

      private

      # Convenience: safely call a block and return { error: } on failure.
      def safe
        yield
      rescue StandardError => e
        Rails.logger.warn "[#{self.class.name}] #{e.class}: #{e.message}"
        { error: e.message }
      end
    end
  end
end
