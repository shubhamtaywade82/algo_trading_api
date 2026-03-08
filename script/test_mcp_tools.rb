#!/usr/bin/env ruby
# frozen_string_literal: true

# Call each MCP tool and check for 200 + JSON-RPC 2.0 response.
# Usage: ruby script/test_mcp_tools.rb [base_url]
# Example: ruby script/test_mcp_tools.rb http://localhost:5002
# Requires MCP_ACCESS_TOKEN (set in .env or export). Script loads .env from project root if present.
# Set SHOW_RESPONSE=1 to print a short preview of each response (default: 1). Set to 0 to hide.
# Tools that need Dhan/OpenAI may return error in result; we only check HTTP 200 + jsonrpc.

require 'net/http'
require 'json'
require 'uri'
require 'date'
require_relative '../config/environment'

def load_dotenv(path)
  return unless File.file?(path)

  File.foreach(path) do |line|
    line = line.strip
    next if line.empty? || line.start_with?('#')

    key, val = line.split('=', 2)
    next unless key

    ENV[key.strip] = val.to_s.strip.gsub(/\A["']|["']\z/, '')
  end
end

script_dir = File.dirname(File.expand_path(__FILE__))
root_dir = File.expand_path('..', script_dir)
load_dotenv(File.join(root_dir, '.env'))

mcp_token = ENV.fetch('MCP_ACCESS_TOKEN', nil)
abort 'MCP_ACCESS_TOKEN is not set. Set it in .env or export it before running this script.' if mcp_token.to_s.strip.empty?

base_url = ARGV[0] || 'http://localhost:5002'
mcp_url = URI.join(base_url.end_with?('/') ? base_url : "#{base_url}/", 'mcp')

headers = {
  'Content-Type' => 'application/json',
  'Accept' => 'application/json, text/event-stream',
  'Authorization' => "Bearer #{mcp_token}"
}

to_date = ENV.fetch('TO_DATE', Time.zone.today.to_s).to_s.strip
from_date = ENV.fetch('FROM_DATE', (Time.zone.today - 1.day).to_s).to_s.strip
expiry = ENV['EXPIRY'].to_s.strip
expiry = nil if expiry.empty?
show_response = ENV['SHOW_RESPONSE'].to_s =~ /\A(1|yes|true)\z/i
preview_len = (ENV['PREVIEW_LEN'] || '380').to_i

def post(uri, body, headers)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == 'https'
  req = Net::HTTP::Post.new(uri.request_uri)
  headers.each { |k, v| req[k] = v }
  req.body = body.is_a?(String) ? body : body.to_json
  http.request(req)
end

def run_tool(mcp_url, headers, name, params, show_response:, preview_len:)
  body = { jsonrpc: '2.0', id: params[:id], method: 'tools/call', params: params[:params] }.to_json
  resp = post(mcp_url, body, headers)
  body_str = resp.body
  ok = resp.code.to_i == 200 && body_str.include?('"jsonrpc":"2.0"')

  if ok
    puts "  OK   #{name}"
    if show_response && body_str.length.positive?
      preview = body_str.length > preview_len ? "#{body_str[0, preview_len]}..." : body_str
      preview.each_line { |line| puts "    #{line.chomp}" }
      puts '' if body_str.length > preview_len
    end
  else
    puts "  FAIL #{name} (HTTP #{resp.code})"
    puts body_str[0, 200]
    puts ''
  end
  ok
end

puts "Testing MCP tools at #{mcp_url}"
puts "  (TO_DATE=#{to_date}, FROM_DATE=#{from_date}, EXPIRY=#{expiry || 'default'})"
puts ''

failed = 0
id = 0

tools = [
  ['get_positions', { name: 'get_positions', arguments: {} }],
  ['get_market_data', { name: 'get_market_data', arguments: { exchange_segment: 'IDX_I', symbol: 'NIFTY' } }],
  ['get_option_chain', { name: 'get_option_chain', arguments: { index: 'NIFTY', expiry: expiry }.compact }],
  ['scan_trade_setup', {
    name: 'scan_trade_setup',
    arguments: { index_symbol: 'NIFTY', expiry_date: expiry, strategy_type: 'intraday' }.compact
  }],
  ['backtest_strategy', {
    name: 'backtest_strategy',
    arguments: { symbol: 'NIFTY', from_date: from_date, to_date: to_date }
  }],
  ['explain_trade', { name: 'explain_trade', arguments: { query: 'What is a covered call?' } }],
  ['place_trade (dry-run)', {
    name: 'place_trade',
    arguments: {
      security_id: '1',
      exchange_segment: 'NSE_EQ',
      transaction_type: 'BUY',
      quantity: 1,
      product_type: 'CNC'
    }
  }],
  ['close_trade (dry-run)', {
    name: 'close_trade',
    arguments: {
      security_id: '1',
      exchange_segment: 'NSE_EQ',
      net_quantity: 1,
      product_type: 'CNC'
    }
  }]
]

tools.each do |name, params|
  id += 1
  failed += 1 unless run_tool(mcp_url, headers, name, { id: id, params: params }, show_response: show_response, preview_len: preview_len)
end

puts ''
if failed.zero?
  puts 'All tools returned 200 + JSON-RPC 2.0.'
else
  puts "#{failed} tool(s) failed."
  exit 1
end
