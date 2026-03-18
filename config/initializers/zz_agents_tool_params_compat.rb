# frozen_string_literal: true

require 'agents'

# Compatibility layer:
# The upstream RubyLLM::Tool DSL exposes declared params via `parameters`,
# while this repo's specs expect `Agents::Tool.params` to return an array of
# param declarations (hashes with :name and :required).
#
# We override `.params` only for the "no args" case used by specs.
#
Agents::Tool.singleton_class.class_eval do
  unless method_defined?(:params_declaration_compat_enabled)
    alias_method :_params_schema_definition_original, :params

    define_method(:params) do |schema = nil, &block|
      if schema.nil? && block.nil?
        parameters.map do |name, param|
          {
            name: name,
            type: param.type,
            description: param.description,
            required: param.required
          }
        end
      else
        _params_schema_definition_original(schema, &block)
      end
    end

    define_method(:params_declaration_compat_enabled) { true }
  end
end

