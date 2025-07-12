module TestStubs
  def stub_charges(amount = 0.0)
    allow(Charges::Calculator).to receive(:call).and_return(amount)
  end

  def stub_spot_ltp(val)
    allow(MarketCache).to receive(:read_ltp).and_return(val)
  end

  def stub_chain_trend(trend)
    allow_any_instance_of(Orders::RiskManager)
      .to receive(:fetch_intraday_trend).and_return(trend)
  end
end

RSpec.configure { |c| c.include TestStubs }