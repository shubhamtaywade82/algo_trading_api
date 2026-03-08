# frozen_string_literal: true

class MarketSentimentController < ApplicationController
  def show
    result = Market::SentimentService.call(params)
    render json: result, status: :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
