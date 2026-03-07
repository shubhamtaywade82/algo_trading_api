#!/usr/bin/env ruby
# frozen_string_literal: true

# Call each MCP tool and check for 200 + JSON-RPC 2.0 response.
# Usage: ruby script/test_mcp_tools.rb [base_url]
# Example: ruby script/test_mcp_tools.rb http://localhost:5002
# Requires MCP_ACCESS_TOKEN (set in .env or export). Script loads .env from project root if present.
# Set TO_DATE / FROM_DATE for date-range tools (default: today / yesterday).
# Set SHOW_RESPONSE=1 to print a short preview of each response (default: 1). Set to 0 to hide.
# Tools that need Dhan credentials may return "Error: ..." in result; we only check HTTP 200 + jsonrpc.

require 'net/http'
require 'json'
require 'uri'
require 'date'

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

if ENV['MCP_ACCESS_TOKEN'].to_s.strip.empty?
  abort 'MCP_ACCESS_TOKEN is not set. Set it in .env or export it before running this script.'
end

base_url = ARGV[0] || 'http://localhost:5002'
mcp_url = URI.join(base_url.end_with?('/') ? base_url : "#{base_url}/", 'mcp')

headers = {
  'Content-Type' => 'application/json',
  'Accept' => 'application/json, text/event-stream',
  'Authorization' => "Bearer #{ENV['MCP_ACCESS_TOKEN']}"
}

to_date = ENV['TO_DATE'].to_s.strip.empty? ? Date.today.to_s : ENV['TO_DATE']
from_date = ENV['FROM_DATE'].to_s.strip.empty? ? (Date.today - 1).to_s : ENV['FROM_DATE']
expiry_symbol = ENV['EXPIRY_SYMBOL'] || 'NIFTY'
expiry_segment = ENV['EXPIRY_SEGMENT'] || 'IDX_I'
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

def fetch_expiry(mcp_url, headers, segment, symbol)
  body = {
    jsonrpc: '2.0', id: 0, method: 'tools/call',
    params: {
      name: 'get_expiry_list',
      arguments: { exchange_segment: segment, symbol: symbol }
    }
  }.to_json
  resp = post(mcp_url, body, headers)
  return nil unless resp.code.to_i == 200

  data = JSON.parse(resp.body)
  return nil unless data['result'] && data['result']['content'] && data['result']['content'][0]

  raw = data['result']['content'][0]['text']
  return nil if raw.to_s.empty?

  json_str = raw.sub(/\A```json?\s*\n/, '').sub(/\n```\s*\z/, '')
  parsed = JSON.parse(json_str)
  if parsed.is_a?(Array) && parsed[0]
    parsed[0].is_a?(String) ? parsed[0] : (parsed[0]['expiry'] || parsed[0]['expiries']&.first)
  elsif parsed['expiry'].is_a?(Array) && parsed['expiry'][0]
    parsed['expiry'][0]
  elsif parsed['expiries'].is_a?(Array) && parsed['expiries'][0]
    parsed['expiries'][0]
  end
rescue JSON::ParserError, TypeError
  nil
end

expiry = ENV['EXPIRY'].to_s.strip
expiry = fetch_expiry(mcp_url, headers, expiry_segment, expiry_symbol) if expiry.empty?
expiry = '2025-02-27' if expiry.to_s.empty?

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
puts "  (TO_DATE=#{to_date}, FROM_DATE=#{from_date}, EXPIRY=#{expiry})"
puts ''

failed = 0
id = 0

[
  ['get_holdings', { name: 'get_holdings', arguments: {} }],
  ['get_positions', { name: 'get_positions', arguments: {} }],
  ['get_fund_limits', { name: 'get_fund_limits', arguments: {} }],
  ['get_order_list', { name: 'get_order_list', arguments: {} }],
  ['get_edis_inquiry', { name: 'get_edis_inquiry', arguments: {} }],
  ['get_order_by_id', { name: 'get_order_by_id', arguments: { order_id: 'test-order-123' } }],
  ['get_order_by_correlation_id', { name: 'get_order_by_correlation_id', arguments: { correlation_id: 'test-corr-1' } }],
  ['get_trade_book', { name: 'get_trade_book', arguments: { order_id: 'test-order-123' } }],
  ['get_trade_history', { name: 'get_trade_history', arguments: { from_date: from_date, to_date: to_date } }],
  ['get_instrument', { name: 'get_instrument', arguments: { exchange_segment: 'IDX_I', symbol: 'SENSEX' } }],
  ['get_instrument NIFTY', { name: 'get_instrument', arguments: { exchange_segment: 'IDX_I', symbol: 'NIFTY' } }],
  ['get_market_ohlc', { name: 'get_market_ohlc', arguments: { exchange_segment: 'NSE_EQ', symbol: 'RELIANCE' } }],
  ['get_expiry_list', { name: 'get_expiry_list', arguments: { exchange_segment: 'IDX_I', symbol: 'NIFTY' } }],
  ['get_option_chain', { name: 'get_option_chain', arguments: { exchange_segment: 'IDX_I', symbol: 'NIFTY', expiry: expiry } }],
  ['get_historical_daily_data', { name: 'get_historical_daily_data', arguments: { exchange_segment: 'NSE_EQ', symbol: 'RELIANCE', from_date: from_date, to_date: to_date } }],
  ['get_intraday_minute_data', { name: 'get_intraday_minute_data', arguments: { exchange_segment: 'NSE_EQ', symbol: 'RELIANCE', from_date: from_date, to_date: to_date } }]
].each do |name, params|
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
