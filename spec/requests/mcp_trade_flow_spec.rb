# frozen_string_literal: true

require 'rails_helper'

MCP_ACCEPT = { 'Accept' => 'application/json, text/event-stream' }.freeze
MCP_AUTH = { 'Authorization' => 'Bearer secret-token' }.freeze

RSpec.describe 'MCP trade flow', :mcp do
  around do |example|
    previous = ENV.fetch('MCP_ACCESS_TOKEN', nil)
    ENV['MCP_ACCESS_TOKEN'] = 'secret-token'
    example.run
  ensure
    ENV['MCP_ACCESS_TOKEN'] = previous
  end

  it 'calls analyze_trade -> resolve_derivative -> place_order' do
    expiry_date = Date.iso8601('2026-03-26')
    selected_strike = 22_450
    option_type = 'CE'

    trade_result = Trading::TradeDecisionEngine::Result.new(
      proceed: true,
      symbol: 'NIFTY',
      direction: option_type,
      expiry: expiry_date.to_s,
      selected_strike: selected_strike,
      iv_rank: 35.0,
      regime: 'normal',
      chain_analysis: { trend: 'up' },
      spot: 200.0,
      reason: nil,
      timestamp: Time.current
    )

    allow(Trading::TradeDecisionEngine).to receive(:call)
      .with(symbol: 'NIFTY', expiry: expiry_date.to_s)
      .and_return(trade_result)

    derivative = instance_double(
      Derivative,
      underlying_symbol: 'NIFTY',
      expiry_date: expiry_date,
      strike_price: selected_strike,
      option_type: option_type,
      security_id: '123456',
      exchange_segment: 'NSE_FNO',
      lot_size: 75,
      symbol_name: 'NIFTY26MAR22450CE',
      display_name: nil,
      underlying_security_id: '999'
    )

    option_chain = {
      oc: {
        selected_strike.to_s => {
          ce: { oi: 2_500, volume: 800 },
          pe: { oi: 200, volume: 100 }
        }
      }
    }

    underlying_instrument = instance_double(Instrument, fetch_option_chain: option_chain)

    allow(Derivative).to receive(:find_by)
      .with(
        underlying_symbol: 'NIFTY',
        expiry_date: expiry_date,
        strike_price: selected_strike,
        option_type: option_type
      )
      .and_return(derivative)

    allow(Instrument).to receive(:find_by!)
      .with(security_id: derivative.underlying_security_id.to_s)
      .and_return(underlying_instrument)

    allow(Positions::ActiveCache).to receive(:refresh!)
    allow(Positions::ActiveCache).to receive(:fetch)
      .with(derivative.security_id, derivative.exchange_segment)
      .and_return(nil)

    allow(Orders::Gateway).to receive(:place_order) do |payload, source:|
      {
        dry_run: true,
        blocked: false,
        message: 'dry-run stub',
        order_id: 'DRY-1',
        order_status: 'DRY',
        payload: payload
      }
    end

    # 1) analyze_trade
    analyze_body = {
      jsonrpc: '2.0',
      id: 1,
      method: 'tools/call',
      params: {
        name: 'analyze_trade',
        arguments: { symbol: 'NIFTY', expiry: expiry_date.to_s }
      }
    }

    post '/mcp',
         params: analyze_body.to_json,
         headers: { 'Content-Type' => 'application/json' }.merge(MCP_ACCEPT).merge(MCP_AUTH)

    expect(response).to have_http_status(:ok)
    analyze_json = response.parsed_body
    analyze_result = analyze_json['result']['structuredContent']
    expect(analyze_result['proceed']).to eq(true)
    expect(analyze_result['selected_strike']).to eq(selected_strike)
    expect(analyze_result['direction']).to eq(option_type)

    # 2) resolve_derivative (args driven by analyze_trade output)
    resolve_body = {
      jsonrpc: '2.0',
      id: 2,
      method: 'tools/call',
      params: {
        name: 'resolve_derivative',
        arguments: {
          symbol: 'NIFTY',
          expiry: analyze_result['expiry'],
          strike: analyze_result['selected_strike'],
          option_type: analyze_result['direction']
        }
      }
    }

    post '/mcp',
         params: resolve_body.to_json,
         headers: { 'Content-Type' => 'application/json' }.merge(MCP_ACCEPT).merge(MCP_AUTH)

    expect(response).to have_http_status(:ok)
    resolve_json = response.parsed_body
    resolve_result = resolve_json['result']['structuredContent']

    expect(resolve_result['security_id']).to eq(derivative.security_id)
    expect(resolve_result['exchange_segment']).to eq(derivative.exchange_segment)
    expect(resolve_result['lot_size']).to eq(derivative.lot_size)

    # 3) place_order (expects broker identifiers)
    place_body = {
      jsonrpc: '2.0',
      id: 3,
      method: 'tools/call',
      params: {
        name: 'place_order',
        arguments: {
          security_id: resolve_result['security_id'],
          exchange_segment: resolve_result['exchange_segment'],
          transaction_type: 'BUY',
          quantity: 1,
          product_type: 'INTRADAY',
          order_type: 'MARKET'
        }
      }
    }

    post '/mcp',
         params: place_body.to_json,
         headers: { 'Content-Type' => 'application/json' }.merge(MCP_ACCEPT).merge(MCP_AUTH)

    expect(response).to have_http_status(:ok)
    place_json = response.parsed_body
    place_result = place_json['result']['structuredContent']

    expect(place_result['dry_run']).to eq(true)
    expect(place_result['blocked']).to eq(false)
    expect(place_result['payload']['exchange_segment']).to eq(derivative.exchange_segment)
  end
end

