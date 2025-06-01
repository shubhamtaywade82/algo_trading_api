# lib/tasks/exit_debug.rake

namespace :exit_debug do
  desc "Simulate and test exit flow for a manual position"

  task :simulate, [:symbol, :entry, :ltp, :spot_ltp] => :environment do |t, args|
    args.with_defaults(symbol: 'NIFTY24JUN18000CE', entry: 100.0, ltp: 142.0, spot_ltp: 18050.0)

    security_id = '123456'
    exchange_segment = 'NSEFO'

    puts "🔧 Injecting position: \#{args.symbol} @ entry \#{args.entry}"
    position = {
      'tradingSymbol'    => args.symbol,
      'securityId'       => security_id,
      'exchangeSegment'  => exchange_segment,
      'buyAvg'           => args.entry.to_f,
      'netQty'           => 75,
      'productType'      => 'INTRADAY',
      'ltp'              => nil
    }

    Rails.cache.write("positions_active_\#{exchange_segment}_\#{security_id}", position)
    Rails.cache.write("ltp_\#{exchange_segment}_\#{security_id}", args.ltp.to_f)
    Rails.cache.write("spot_ltp_NIFTY", args.spot_ltp.to_f)

    pos = Rails.cache.read("positions_active_\#{exchange_segment}_\#{security_id}")
    pos['ltp'] = Rails.cache.read("ltp_\#{exchange_segment}_\#{security_id}")

    puts "📊 Running Analyzer..."
    analysis = Orders::Analyzer.call(pos)

    puts "🧠 Running RiskManager..."
    decision = Orders::RiskManager.call(pos, analysis)

    puts "✅ Position:"
    pp pos

    puts "📈 Analysis:"
    pp analysis

    puts "📌 Decision:"
    pp decision
  end
end
