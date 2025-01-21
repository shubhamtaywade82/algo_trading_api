# frozen_string_literal: true

module ExchangeSegmentHelper
  def exchange_segment
    segment_mapping = {
      %i[nse index] => 'IDX_I',
      %i[bse index] => 'IDX_I',
      %i[nse equity] => 'NSE_EQ',
      %i[bse equity] => 'BSE_EQ',
      %i[nse derivatives] => 'NSE_FNO',
      %i[bse derivatives] => 'BSE_FNO',
      %i[nse currency] => 'NSE_CURRENCY',
      %i[bse currency] => 'BSE_CURRENCY'
    }
    segment_mapping[[exchange.to_sym,
                     segment.to_sym]] || (raise "Unsupported exchange and segment combination: #{exchange}, #{segment}")
  end
end
