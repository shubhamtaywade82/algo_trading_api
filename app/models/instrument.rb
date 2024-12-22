class Instrument < ApplicationRecord
  # Define the enum for instrument_type with string mapping
  enum :instrument_type, {
    "FUTCUR" => "FUTCUR",
    "OPTCUR" => "OPTCUR",
    "OPTIDX" => "OPTIDX",
    "FUTIDX" => "FUTIDX",
    "OPTSTK" => "OPTSTK",
    "FUTSTK" => "FUTSTK",
    "ES" => "ES",
    "Other" => "Other",
    "ETF" => "ETF",
    "MF" => "MF",
    "InvITU" => "InvITU",
    "REIT" => "REIT",
    "EQ" => "EQ",
    "PS" => "PS",
    "CB" => "CB",
    "DBT" => "DBT",
    "DEB" => "DEB",
    "TB" => "TB",
    "GB" => "GB",
    "PN" => "PN",
    "PTC" => "PTC",
    "INDEX" => "INDEX",
    "IDX" => "IDX",
    "FUTCOM" => "FUTCOM",
    "OPTFUT" => "OPTFUT",
    "CUR OP" => "CUR OP",
    "FUT" => "FUT",
    "OP" => "OP"
  }, prefix: :instrument_type

  # Define the enum for segment with string mapping
  enum :segment, {
    "C" => "C",  # Currency
    "D" => "D",  # Derivative
    "E" => "E",  # Equity
    "I" => "I",  # Index
    "M" => "M"   # Commodity
  }, prefix: :segment

  # Define expiry_flag without prefix
  enum :expiry_flag, {
    "1" => "1",  # Immediate
    "H" => "H",  # Half Yearly
    "M" => "M",  # Monthly
    "Q" => "Q",  # Quarterly
    "W" => "W"   # Weekly
  }, prefix: true

  has_one :mis_detail, dependent: :destroy

  # Validation
  validates :instrument_type, inclusion: { in: Instrument.instrument_types.keys }
  validates :segment, inclusion: { in: Instrument.segments.keys }

  # Scopes
  scope :equities, -> { where(instrument_type: "EQ") }
  scope :indices, -> { where(instrument_type: "INDEX") }
  scope :currencies, -> { where(segment: "C") }
  scope :expiring_soon, -> { where(expiry_flag: "1") }

  # Instance Methods
  def display_name
    "#{name} (#{instrument_type})"
  end

  def full_segment_name
    case segment
    when "C" then "Currency"
    when "D" then "Derivative"
    when "E" then "Equity"
    when "I" then "Index"
    when "M" then "Commodity"
    else "Unknown"
    end
  end

  def ltp
    response = Dhanhq::API::MarketFeed.ltp(data: { segment => [security_id]})
    response[:status] == "success" ? response[:data] : nil
  end

  def fetch_option_chain(expiry)
    Dhanhq::API::Option.chain(
      UnderlyingScrip: security_id,
      UnderlyingSeg: segment,
      Expiry: expiry
    )
  end
end
