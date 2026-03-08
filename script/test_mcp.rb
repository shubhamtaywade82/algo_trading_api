#!/usr/bin/env ruby
# frozen_string_literal: true

# Test the POST /mcp endpoint (JSON-RPC 2.0, Streamable HTTP).
# Usage: ruby script/test_mcp.rb [base_url]
# Example: ruby script/test_mcp.rb http://localhost:5002
# Requires the Rails server to be running.
# Requires MCP_ACCESS_TOKEN (set in .env or export). Script loads .env from project root if present.

require 'net/http'
require 'json'
require 'uri'

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

def post(uri, body, headers)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == 'https'
  req = Net::HTTP::Post.new(uri.request_uri)
  headers.each { |k, v| req[k] = v }
  req.body = body
  http.request(req)
end

puts "Testing MCP at #{mcp_url}"
puts ''

# 1. Empty body -> 400, parse error
print '1. Empty body (expect 400, Parse error)... '
resp = post(mcp_url, '', headers)
body_str = resp.body
ok = resp.code.to_i == 400 && (
  (body_str.include?('"code":-32700') && body_str.include?('Parse error')) ||
  body_str.include?('Invalid JSON')
)
if ok
  puts 'OK (400, parse error)'
else
  puts "FAIL (got HTTP #{resp.code}, body: #{body_str[0, 200]})"
  exit 1
end

# 2. tools/list -> 200, jsonrpc 2.0
print '2. tools/list (expect 200, jsonrpc 2.0)... '
body = { jsonrpc: '2.0', id: 1, method: 'tools/list' }.to_json
resp = post(mcp_url, body, headers)
if resp.code.to_i == 200 && resp.body.include?('"jsonrpc":"2.0"')
  puts 'OK (200, jsonrpc 2.0)'
else
  puts "FAIL (got HTTP #{resp.code})"
  puts resp.body[0, 200]
  puts '...'
  exit 1
end

# 3. tools/call get_instrument
print '3. tools/call get_instrument IDX_I SENSEX (expect 200)... '
body = {
  jsonrpc: '2.0',
  id: 2,
  method: 'tools/call',
  params: {
    name: 'get_instrument',
    arguments: { exchange_segment: 'IDX_I', symbol: 'SENSEX' }
  }
}.to_json
resp = post(mcp_url, body, headers)
if resp.code.to_i == 200 && resp.body.include?('"jsonrpc":"2.0"')
  puts 'OK (200, valid JSON-RPC response)'
else
  puts "FAIL (got HTTP #{resp.code})"
  puts resp.body[0, 300]
  puts '...'
  exit 1
end

puts ''
puts 'All MCP checks passed.'
