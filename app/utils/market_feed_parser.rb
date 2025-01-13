# frozen_string_literal: true

class MarketFeedParser
  def self.parse(io, fields)
    fields.index_with do |field|
      read_field(io, field)
    end
  rescue StandardError => e
    raise "Market feed parsing failed: #{e.message}"
  end

  def self.read_field(io, field)
    case field
    when :last_traded_price then io.read(4).unpack1('F')
    when :volume then io.read(4).unpack1('N')
      # Add cases for other field types
    end
  end
end
