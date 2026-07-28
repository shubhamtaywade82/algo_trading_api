# frozen_string_literal: true

namespace :telegram do
  desc 'Register all bot commands with Telegram Bot API so autocomplete menu shows up in chat'
  task set_commands: :environment do
    commands = [
      { command: 'help', description: 'Show all available bot commands & guide' },
      { command: 'portfolio', description: 'Quick portfolio summary' },
      { command: 'positions', description: 'Live open positions & P&L' },
      { command: 'portfolio_full', description: 'Full institutional risk analysis' },
      { command: 'funds', description: 'Account funds, margin & collateral limits' },
      { command: 'nifty_analysis', description: 'NIFTY technical & option chain report' },
      { command: 'bank_nifty_analysis', description: 'BANKNIFTY analysis' },
      { command: 'sensex_analysis', description: 'SENSEX analysis' },
      { command: 'nifty_options', description: 'NIFTY options buying trade setup' },
      { command: 'banknifty_options', description: 'BANKNIFTY options buying setup' },
      { command: 'sensex_options', description: 'SENSEX options buying setup' },
      { command: 'options_avoid_check', description: 'Check if IV/VIX favors buying options' },
      { command: 'oi_snapshot', description: 'NIFTY ATM Open Interest & IV snapshot' },
      { command: 'market_summary', description: 'Live index prices & India VIX' },
      { command: 'expiry_roadmap', description: 'Index expiry roadmap & ATM IV' },
      { command: 'screener', description: 'Run NIFTY 100 stock screener' },
      { command: 'market_sentiment', description: 'Market sentiment & institutional flow' },
      { command: 'crypto_analysis', description: 'Crypto SMC multi-timeframe report (e.g. BTCUSDT)' },
      { command: 'crypto_scan', description: 'Scan crypto futures pairs for setups' },
      { command: 'crypto_config', description: 'Show active crypto scanner settings' }
    ]

    res = TelegramNotifier.set_my_commands(commands)
    if res.is_a?(Net::HTTPSuccess)
      puts "✅ Successfully registered #{commands.size} commands with Telegram Bot API."
    else
      puts "❌ Failed to register commands with Telegram: #{res&.body}"
    end
  end
end
