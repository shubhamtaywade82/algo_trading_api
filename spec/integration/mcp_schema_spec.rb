# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'MCP Schema Consistency', type: :integration do
  let(:tools) { Mcp::ProductionToolRegistry.tools }
  let(:openapi_path) { Rails.root.join('docs/mcp_openapi.yaml') }
  let(:openapi_content) { YAML.load_file(openapi_path) if File.exist?(openapi_path) }

  it 'ensures all registered tools follow the MCP spec' do
    tools.each do |tool_class|
      definition = tool_class.definition

      # 1. Basic structure
      expect(definition).to have_key(:name), "Tool #{tool_class} missing :name"
      expect(definition).to have_key(:description), "Tool #{tool_class} missing :description"
      expect(definition).to have_key(:inputSchema), "Tool #{tool_class} missing :inputSchema"

      # 2. InputSchema quality (Crucial for GPT decision making)
      schema = definition[:inputSchema]
      expect(schema[:type]).to eq('object'), "Tool #{tool_class} inputSchema must be type: object"
      expect(schema).to have_key(:properties), "Tool #{tool_class} inputSchema missing :properties"

      # 3. Property Descriptions (GPTs fail without these)
      schema[:properties].each do |prop_name, prop_meta|
        expect(prop_meta).to have_key(:description), 
          "Tool #{tool_class.name}, parameter '#{prop_name}' is missing a description. GPT will not know how to use it!"
      end
    end
  end

  it 'ensures the OpenAPI documentation is present' do
    expect(File.exist?(openapi_path)).to be true
  end

  # Optional: Ensure tools in Ruby are at least mentioned in your GPT instructions or OpenAPI
  # For now, let's just make sure they are valid JSON-RPC compatible
  it 'validates tool execution signature' do
    tools.each do |tool_class|
      expect(tool_class).to respond_to(:execute), "Tool #{tool_class} must implement self.execute(args)"
    end
  end
end
