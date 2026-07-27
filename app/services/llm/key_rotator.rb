# frozen_string_literal: true

module Llm
  # Rotates a pool of Ollama Cloud API keys, quarantining any that fail.
  #
  # Ollama Cloud authenticates per request with a bearer token, and one key is
  # a single point of failure: rate limits are counted per key, and a revoked
  # or exhausted key takes the whole AI layer down with it. Up to five keys are
  # read from `OLLAMA_API_KEY_1..5` and tried in order.
  #
  # Each attempt gets its own `RubyLLM.context` — an isolated copy of the
  # global configuration — so rotating never mutates process-wide state. That
  # matters here: the market-feed thread and web requests share this process,
  # and a global `RubyLLM.configure` from one request would change the key
  # underneath the other.
  #
  # Nothing in this class places orders or reads credentials beyond the LLM
  # keys; the AI layer proposes, `Strategy::Validator` and `Orders::Gateway`
  # decide.
  class KeyRotator
    MAX_KEYS = 5
    QUARANTINE = 5.minutes
    DEFAULT_API_BASE = 'https://ollama.com/v1'
    DEFAULT_MODEL = 'gpt-oss:120b'

    # Failures that mean "this key is no good right now".
    #
    # A bad request, an unknown model or a malformed tool call is the caller's
    # fault: it would fail identically on all five keys, so it is raised
    # straight through rather than burning the pool.
    ROTATABLE_ERRORS = [
      RubyLLM::UnauthorizedError,
      RubyLLM::ForbiddenError,
      RubyLLM::PaymentRequiredError,
      RubyLLM::RateLimitError,
      RubyLLM::ServerError,
      RubyLLM::ServiceUnavailableError,
      RubyLLM::OverloadedError
    ].freeze

    # Raised when every configured key has been tried and quarantined.
    class Error < StandardError; end

    class << self
      # Runs a block against the first healthy key, rotating past any that
      # fail, and returns whatever the block returns.
      #
      # @yieldparam context [RubyLLM::Context] bound to one API key
      # @yieldparam index [Integer] 1-based key number, for logging
      # @return [Object] the block's value
      # @raise [Error] when no key could serve the request
      def with_key
        keys = available_keys
        raise Error, exhausted_message if keys.empty?

        last_error = nil
        keys.each do |key, index|
          # `return` rather than falling out of the loop: the block's value is
          # the whole point of the call, and swallowing it here would hand every
          # caller a silent nil.
          return yield(build_context(key), index).tap { revive(index) }
        rescue *ROTATABLE_ERRORS => e
          last_error = e
          quarantine(index, e)
        end

        raise Error, "all #{keys.size} Ollama key(s) failed; last error: #{last_error.class} - #{last_error.message}"
      end

      # One-shot prompt with rotation.
      #
      # @param prompt [String]
      # @param system [String, nil] system instructions
      # @param model [String, nil] defaults to OLLAMA_DEFAULT_MODEL
      # @return [String] the reply text
      def ask(prompt, system: nil, model: nil)
        with_key do |context, _index|
          chat = build_chat(context, model: model)
          chat.with_instructions(system) if system.present?
          chat.ask(prompt).content.to_s
        end
      end

      # A chat bound to one key, for callers that need tools or a schema.
      # The block runs inside the rotation, so a mid-conversation key failure
      # restarts it on the next key.
      #
      # @yieldparam chat [RubyLLM::Chat]
      # @return [Object] the block's value
      def with_chat(model: nil)
        with_key do |context, _index|
          yield build_chat(context, model: model)
        end
      end

      # @return [Boolean] whether any key is configured at all
      def configured?
        configured_keys.any?
      end

      # Per-key state, for diagnostics. Never returns the keys themselves.
      #
      # @return [Array<Hash>]
      def health
        configured = configured_keys.map(&:last)
        (1..MAX_KEYS).map do |index|
          until_at = quarantined_until(index)
          {
            key: index,
            configured: configured.include?(index),
            quarantined_until: until_at,
            state: key_state(configured.include?(index), until_at)
          }
        end
      end

      # Clears quarantines. Used by the diagnostics task and by tests.
      def reset!
        mutex.synchronize { quarantines.clear }
      end

      def default_model
        ENV['OLLAMA_DEFAULT_MODEL'].presence || DEFAULT_MODEL
      end

      # Ollama Cloud speaks the OpenAI-compatible API, and RubyLLM's Ollama
      # provider posts to `{api_base}/chat/completions`, so the base has to
      # carry the `/v1` — without it every request 404s.
      def api_base
        ENV['OLLAMA_API_BASE'].presence || DEFAULT_API_BASE
      end

      private

      def build_chat(context, model: nil)
        # Cloud model ids are not in RubyLLM's bundled registry, so the model
        # must be asserted rather than looked up; that in turn requires naming
        # the provider explicitly.
        context.chat(model: model || default_model, provider: :ollama, assume_model_exists: true)
      end

      def build_context(api_key)
        RubyLLM.context do |config|
          config.ollama_api_base = api_base
          config.ollama_api_key = api_key
        end
      end

      # Read from the environment on every call rather than memoised: a
      # long-running process should pick up a rotated key without a restart.
      #
      # @return [Array<Array(String, Integer)>] [key, 1-based index] pairs
      def configured_keys
        (1..MAX_KEYS).filter_map do |index|
          key = ENV["OLLAMA_API_KEY_#{index}"].presence
          [key, index] if key
        end
      end

      def available_keys
        now = Time.current
        configured_keys.reject do |_key, index|
          expiry = quarantined_until(index)
          expiry && expiry > now
        end
      end

      def quarantine(index, error)
        mutex.synchronize { quarantines[index] = Time.current + QUARANTINE }
        Rails.logger.warn("[Llm::KeyRotator] key ##{index} quarantined for #{QUARANTINE.inspect}: " \
                          "#{error.class} - #{error.message}")
      end

      def revive(index)
        mutex.synchronize { quarantines.delete(index) }
      end

      def quarantined_until(index)
        mutex.synchronize { quarantines[index] }
      end

      def key_state(configured, quarantined_until)
        return 'not configured' unless configured
        return 'quarantined' if quarantined_until && quarantined_until > Time.current

        'available'
      end

      def exhausted_message
        return 'no Ollama API keys configured (set OLLAMA_API_KEY_1..5)' if configured_keys.empty?

        next_free = mutex.synchronize { quarantines.values.min }
        "all #{configured_keys.size} Ollama key(s) are quarantined until #{next_free&.iso8601}"
      end

      def quarantines
        @quarantines ||= {}
      end

      def mutex
        @mutex ||= Mutex.new
      end
    end
  end
end
