# frozen_string_literal: true

namespace :llm do
  desc 'Show which Ollama Cloud keys are configured and whether any are quarantined'
  task keys: :environment do
    Llm::KeyRotator.health.each do |row|
      icon = { 'available' => '✅', 'quarantined' => '⏳', 'not configured' => '➖' }[row[:state]]
      suffix = row[:quarantined_until] ? " until #{row[:quarantined_until].iso8601}" : ''
      puts format('  key #%<key>d  %<icon>s %<state>s%<suffix>s',
                  key: row[:key], icon: icon, state: row[:state], suffix: suffix)
    end
    puts "\nbase=#{Llm::KeyRotator.api_base}  model=#{Llm::KeyRotator.default_model}"
  end

  desc 'Send a one-token probe through every configured key to see which actually work'
  task check_keys: :environment do
    abort('❌ no keys configured; set OLLAMA_API_KEY_1..5') unless Llm::KeyRotator.configured?

    Llm::KeyRotator.reset!
    (1..Llm::KeyRotator::MAX_KEYS).each do |index|
      key = ENV["OLLAMA_API_KEY_#{index}"].presence
      next puts("  key ##{index}: ➖ not configured") unless key

      context = RubyLLM.context do |config|
        config.ollama_api_base = Llm::KeyRotator.api_base
        config.ollama_api_key = key
      end
      chat = context.chat(model: Llm::KeyRotator.default_model, provider: :ollama, assume_model_exists: true)
      reply = chat.ask('Reply with the single word: OK').content.to_s.strip

      puts "  key ##{index}: ✅ healthy (#{reply.truncate(40)})"
    rescue StandardError => e
      puts "  key ##{index}: ❌ #{e.class} - #{e.message}"
    end
  end

  desc 'Ask the trading agent a question. PROMPT="..." [MODEL=...]'
  task ask: :environment do
    prompt = ENV['PROMPT'].presence || abort('❌ set PROMPT="your question"')
    puts Llm::TradingAgent.analyze(prompt, model: ENV.fetch('MODEL', nil))
  end

  desc 'Generate and validate a trade proposal. SYMBOL=NIFTY [DIRECTION=CE]'
  task propose: :environment do
    result = Llm::TradingAgent.propose(symbol: ENV.fetch('SYMBOL', 'NIFTY'), direction: ENV.fetch('DIRECTION', nil))

    puts result[:raw]
    puts "\n--- parsed ---"
    pp result[:proposal]
    puts "\n--- validation (Strategy::Validator decides, not the model) ---"
    pp result[:validation]
  end
end
