# frozen_string_literal: true

# HTTP interface for the AI agent cluster.
#
# All endpoints are read-only from an execution perspective — they produce
# analysis and proposals but NEVER place orders directly. Execution is always
# done through the deterministic engine via the Strategy::Validator gate.
#
# Authentication: Bearer token via AI_AGENTS_ACCESS_TOKEN env var.
#
# Endpoints:
#   POST /ai_agents/analyze        — market structure + options flow analysis
#   POST /ai_agents/propose        — full trade proposal pipeline
#   POST /ai_agents/ask            — operational/debug query
#   GET  /ai_agents/positions      — position review
#   GET  /ai_agents/session_report — full session report
class AiAgentsController < ApplicationController
  before_action :authenticate!

  # POST /ai_agents/analyze
  # Body: { symbol: "NIFTY", candle: "15m" }
  def analyze
    symbol = require_param!(:symbol)
    candle = params[:candle] || '15m'

    result = AI::TradeBrain.analyze(symbol, candle: candle)
    render json: serialized_result(result)
  end

  # POST /ai_agents/propose
  # Body: { symbol: "NIFTY", direction: "CE" }
  def propose
    symbol    = require_param!(:symbol)
    direction = params[:direction]

    result   = AI::TradeBrain.propose(symbol: symbol, direction: direction)
    proposal = result[:proposal]

    validation = proposal ? Strategy::Validator.validate(proposal) : nil

    render json: {
      runner_success: result[:success],
      proposal:       proposal,
      validation:     validation,
      ready_to_trade: proposal.present? && validation&.dig(:valid) == true
    }
  end

  # POST /ai_agents/ask
  # Body: { question: "Why did trade #214 exit early?" }
  def ask
    question = require_param!(:question)

    result = AI::TradeBrain.ask(question)
    render json: { answer: result[:answer], success: result[:success] }
  end

  # GET /ai_agents/positions
  def positions
    result = AI::TradeBrain.review_positions
    render json: { answer: result[:answer], success: result[:success] }
  end

  # GET /ai_agents/session_report
  # Query param: ?symbol=NIFTY
  def session_report
    symbol = params[:symbol]&.upcase || 'NIFTY'
    result = AI::TradeBrain.session_report(symbol)
    render json: result
  end

  private

  def authenticate!
    token = ENV['AI_AGENTS_ACCESS_TOKEN'].presence
    return if token.blank?  # disabled when not configured

    provided = request.headers['Authorization'].to_s.delete_prefix('Bearer ').strip
    render json: { error: 'Unauthorized' }, status: :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(provided, token)
  end

  def require_param!(key)
    val = params[key].to_s.strip
    render json: { error: "#{key} is required" }, status: :unprocessable_entity and return if val.blank?

    val
  end
end
