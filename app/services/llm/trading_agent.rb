# frozen_string_literal: true

module Llm
  # Trading-desk analyst backed by Ollama Cloud, with tool access to this
  # app's live DhanHQ data.
  #
  # This is the single-model counterpart to `AI::TradeBrain`, which orchestrates
  # the multi-agent cluster. Both stop at a *proposal*: execution stays behind
  # `Strategy::Validator` and `Orders::Gateway`, and no tool exposed here can
  # place an order.
  class TradingAgent
    SYSTEM_PROMPT = <<~PROMPT
      You are an analyst on an Indian derivatives desk (NSE/BSE). You cover
      index options, equities, futures and commodities.

      Working rules:
      - Fetch data with the tools before answering. Never guess a price, a
        strike, an expiry or a balance.
      - You propose; you never execute. There is no tool that places an order,
        and a proposal is reviewed by a deterministic validator before anything
        reaches a broker.
      - State the instrument, expiry, strike and side (CE/PE, long/short)
        explicitly. An ambiguous proposal is useless downstream.
      - Always give entry, stop-loss and target, and say what the stop is based
        on (ATR, structure, a fixed percentage).
      - Size against the capital band from the funds tool. Say the margin
        required and the worst-case loss.
      - If the data does not support a trade, say so and stop. "No trade" is a
        valid answer and a cheaper one than a bad fill.
      - Times are IST. Be concise: this is read on a phone during market hours.
    PROMPT

    TOOLS = [
      Llm::Tools::OptionChain,
      Llm::Tools::Candles,
      Llm::Tools::Funds,
      Llm::Tools::Positions,
      Llm::Tools::MarketSentiment
    ].freeze

    class << self
      # Analysis with full tool access.
      #
      # @param prompt [String]
      # @param model [String, nil]
      # @return [String]
      def analyze(prompt, model: nil)
        KeyRotator.with_chat(model: model) do |chat|
          chat.with_instructions(SYSTEM_PROMPT)
            .with_tools(*TOOLS)
            .ask(prompt)
            .content.to_s
        end
      end

      # A question that needs no live data.
      #
      # @return [String]
      def ask(question, model: nil)
        KeyRotator.ask(question, system: SYSTEM_PROMPT, model: model)
      end

      # A trade proposal in the shape `Strategy::Validator` checks.
      #
      # The validator is the gate, not the model: this returns the proposal and
      # the validation result together so a caller never sees an unchecked one.
      #
      # @param symbol [String]
      # @param direction [String, nil] "CE" or "PE"
      # @return [Hash] :proposal, :validation, :raw
      def propose(symbol:, direction: nil, model: nil)
        hint = direction.present? ? " Prefer #{direction.to_s.upcase} if the data supports it." : ''
        raw = analyze(<<~PROMPT, model: model)
          Propose one options trade on #{symbol} for the current session.#{hint}

          Answer with a single JSON object and nothing else, using these keys:
          symbol, direction (CE or PE), strike, entry_price, stop_loss, target,
          confidence (0-1), product (INTRADAY, MARGIN or CNC), rationale.
        PROMPT

        proposal = extract_json(raw)
        {
          raw: raw,
          proposal: proposal,
          validation: proposal ? Strategy::Validator.validate(proposal) : nil
        }
      end
    end

    # Models wrap JSON in prose or a fenced block however they please, so take
    # the outermost object rather than trusting the whole reply to parse.
    def self.extract_json(text)
      candidate = text.to_s[/\{.*\}/m]
      return nil if candidate.blank?

      JSON.parse(candidate)
    rescue JSON::ParserError => e
      Rails.logger.warn("[Llm::TradingAgent] proposal was not valid JSON: #{e.message}")
      nil
    end
  end
end
