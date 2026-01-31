# frozen_string_literal: true

module Market
  # Ensures AI analysis responses include mandatory CLOSE RANGE and Bias lines.
  # Appends them from market data when the model omits them.
  # Corrects SL ₹ and T1 ₹ when they don't match stated % and entry.
  class AnalysisResponseNormalizer
    BIAS_LINE = /\bBias:\s*(CALLS|PUTS|NEUTRAL)\b/i
    CLOSE_RANGE_LINE = /\bCLOSE\s+RANGE:\s*₹/i
    RUPEES = /₹(\d+(?:\.\d+)?)/
    SL_PATTERN = /SL\s*-(\d+)%\s*[=⇒]\s*₹(\d+(?:\.\d+)?)/
    T1_PATTERN = /T1\s*\+(\d+)%\s*[=⇒]\s*₹(\d+(?:\.\d+)?)/
    # Model sometimes writes "T1 ₹= entry × (1 + T1%)=+15% ₹190.95"
    T1_ALT_PATTERN = /=\s*\+(\d+)%\s*₹(\d+(?:\.\d+)?)/
    BIAS_CALLS_BEARISH = /\*\*Bias:\*\*\s*Calls\s+due to super-trend bearish/i

    def initialize(answer, md)
      @answer = answer.to_s
      @md = md || {}
    end

    def call
      out = @answer.dup
      fix_bias_calls_when_bearish!(out)
      correct_sl_t1_rupees!(out)
      out = append_close_range(out) unless out.match?(CLOSE_RANGE_LINE)
      out = append_bias(out) unless out.match?(BIAS_LINE)
      out.strip
    end

    private

    def append_close_range(text)
      line = computed_close_range
      return text if line.blank?

      text << "\n\n#{line}"
    end

    def append_bias(text)
      bias = inferred_bias
      text << "\n\nBias: #{bias}"
    end

    def computed_close_range
      mid = @md.dig(:boll, :middle)&.to_f
      atr = @md[:atr]&.to_f
      ltp = @md[:ltp]&.to_f
      vix = @md[:vix]&.to_f

      return nil if mid.blank? || atr.blank? || ltp.blank?

      base_move = [atr, 0.0075 * ltp].min
      base_move *= 1.2 if vix && vix > 14
      base_move *= 0.8 if vix && vix < 10

      low = mid - base_move
      high = mid + base_move

      step = symbol_round_step
      low_r = (low / step).round * step
      high_r = (high / step).round * step

      low_pct = ((low_r - ltp) / ltp * 100).round(2)
      high_pct = ((high_r - ltp) / ltp * 100).round(2)

      "CLOSE RANGE: ₹#{low_r}–₹#{high_r} (#{low_pct}% to #{high_pct}% from LTP)"
    end

    def symbol_round_step
      sym = @md[:symbol].to_s
      sym.include?('BANK') ? 10 : 5
    end

    def inferred_bias
      super_sig = @md[:super].to_s.downcase
      pa = @md[:price_action] || {}
      last_bullish = pa[:last_candle_bullish]

      return 'NEUTRAL' if last_bullish.nil?

      if super_sig == 'bearish' && !last_bullish
        'PUTS'
      elsif super_sig == 'bullish' && last_bullish
        'CALLS'
      else
        'NEUTRAL'
      end
    end

    def fix_bias_calls_when_bearish!(text)
      text.gsub!(BIAS_CALLS_BEARISH, '**Bias:** PUTS due to super-trend bearish')
    end

    def correct_sl_t1_rupees!(text)
      lines = text.each_line.map do |line|
        has_sl = line.match?(SL_PATTERN)
        has_t1 = line.match?(T1_PATTERN)
        has_t1_alt = line.match?(T1_ALT_PATTERN)
        next line unless has_sl || has_t1 || has_t1_alt

        amounts = line.scan(RUPEES).map { |(n)| n.to_f }
        out = line.dup

        if has_sl
          stated_sl = line[SL_PATTERN, 2].to_f
          entry = (amounts - [stated_sl]).first
          if entry && entry >= 1
            out = out.gsub(SL_PATTERN) do
              pct = Regexp.last_match(1).to_i
              stated = Regexp.last_match(2).to_f
              correct = (entry * (100 - pct) / 100.0).round(2)
              (stated - correct).abs <= 0.02 ? Regexp.last_match(0) : "SL -#{pct}% ⇒ ₹#{correct}"
            end
          end
        end

        if has_t1
          stated_t1 = line[T1_PATTERN, 2].to_f
          amounts_after_sl = out.scan(RUPEES).map { |(n)| n.to_f }
          entry = (amounts_after_sl - [stated_t1]).first
          if entry && entry >= 1
            out = out.gsub(T1_PATTERN) do
              pct = Regexp.last_match(1).to_i
              stated = Regexp.last_match(2).to_f
              correct = (entry * (100 + pct) / 100.0).round(2)
              (stated - correct).abs <= 0.02 ? Regexp.last_match(0) : "T1 +#{pct}% ⇒ ₹#{correct}"
            end
          end
        end

        if has_t1_alt
          stated_t1 = line[T1_ALT_PATTERN, 2].to_f
          amounts_after_t1 = out.scan(RUPEES).map { |(n)| n.to_f }
          entry = (amounts_after_t1 - [stated_t1]).first
          if entry && entry >= 1
            out = out.gsub(T1_ALT_PATTERN) do
              pct = Regexp.last_match(1).to_i
              stated = Regexp.last_match(2).to_f
              correct = (entry * (100 + pct) / 100.0).round(2)
              (stated - correct).abs <= 0.02 ? Regexp.last_match(0) : "T1 +#{pct}% ⇒ ₹#{correct}"
            end
          end
        end
        out
      end
      text.replace(lines.join)
    end
  end
end
