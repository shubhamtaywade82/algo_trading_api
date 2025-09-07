# PriceMath Module Implementation Summary

## Overview
This document summarizes the implementation of the `PriceMath` module across the algo trading API to ensure all **DhanHQ API-related price values** are properly rounded according to DhanHQ tick size requirements (0.05).

**Important Note**: PriceMath is used ONLY for actual trading prices (order prices, LTP, entry prices, etc.) that are sent to or received from DhanHQ APIs. Technical indicators, calculations, and display values continue to use `.round(2)` for consistency.

## PriceMath Module (`lib/price_math.rb`)

The module provides the following methods:
- `round_tick(x)` - Rounds to nearest valid tick
- `floor_tick(x)` - Floors to nearest valid tick below
- `ceil_tick(x)` - Ceils to nearest valid tick above
- `valid_tick?(x)` - Validates if price aligns with tick size
- `round_legacy(x)` - Backward compatibility for 2-decimal rounding

## Files Updated

### Core Services (DhanHQ API Values)
1. **`app/services/orders/analyzer.rb`**
   - Entry price rounding
   - PnL percentage calculation
   - LTP fetching and rounding

2. **`app/services/charges/calculator.rb`**
   - Entry and LTP price rounding
   - Final total calculation

3. **`app/services/orders/bracket_placer.rb`**
   - Stop loss and take profit calculations

4. **`app/services/orders/risk_manager.rb`**
   - Emergency exit notifications
   - Take profit notifications
   - Trailing stop loss adjustments

### Alert Processors (DhanHQ API Values)
5. **`app/services/alert_processors/index.rb`**
   - Stop loss, target, and trail jump calculations
   - Margin requirement logging
   - Cost calculations for lot allocations

6. **`app/services/alert_processors/stock.rb`**
   - Order payload price and trigger price
   - Margin calculations

7. **`app/services/alert_processors/mcx_commodity.rb`**
   - Per lot cost logging

### Market Services (DhanHQ API Values)
8. **`app/services/market/analysis_service.rb`**
   - OHLC values (open, high, low, close) - **These are actual price data**
   - **Technical indicators (ATR, RSI, MACD, EMA) - KEPT as .round(2)**
   - **Options chain display (LTP, IV, OI, Greeks) - KEPT as .round(2)**

9. **`app/services/market/analysis_updater.rb`**
   - **ATR calculations and logging - KEPT as .round(2)**

10. **`app/services/market/prompt_builder.rb`**
    - **Options chain formatting - KEPT as .round(2)**

### Data Models (DhanHQ API Values)
11. **`app/models/candle.rb`**
    - OHLC initialization - **These are actual price data**

12. **`app/models/quote.rb`**
    - LTP display formatting - **This is actual price data**

### Other Services (DhanHQ API Values)
13. **`app/services/catalog/factor_score_engine.rb`**
    - **Price momentum, volatility, and trend calculations - KEPT as .round(2)**
    - **ATR calculations - KEPT as .round(2)**

14. **`app/services/dhan/ws/feed_listener.rb`**
    - LTP cache updates - **This is actual price data from DhanHQ**

15. **`app/services/portfolio_insights/institutional_analyzer.rb`**
    - **Price validation - KEPT as .to_f (not a DhanHQ API value)**

18. **`app/controllers/options_controller.rb`**
    - **IV rank calculations - KEPT as .round(2) (technical calculation)**

## What Uses PriceMath vs .round(2)

### ✅ **PriceMath (DhanHQ API Values)**
- Order entry prices
- Stop loss prices
- Take profit prices
- LTP (Last Traded Price)
- Margin calculations
- Cost per lot
- OHLC candle data
- Quote LTP values

### 🔄 **Kept as .round(2) (Technical/Display Values)**
- Technical indicators (ATR, RSI, MACD, EMA)
- Greeks (Delta, Gamma, Vega, Theta)
- IV (Implied Volatility)
- OI (Open Interest)
- Percentage calculations
- Statistical calculations
- Display formatting

## Testing

A comprehensive test suite has been created in `spec/lib/price_math_spec.rb` covering:
- Tick rounding functionality
- Edge cases (nil, zero, negative values)
- Floor and ceiling operations
- Tick validation
- Backward compatibility

## Benefits

1. **DhanHQ Compliance**: All **trading prices** now align with the 0.05 tick size requirement
2. **Consistency**: Uniform price handling for **actual trading operations**
3. **Accuracy**: Eliminates floating-point precision issues in **order placement**
4. **Maintainability**: Centralized price logic for **trading operations**
5. **Technical Accuracy**: Technical indicators maintain their precision with `.round(2)`

## Usage Examples

```ruby
# For DhanHQ API values (order prices, LTP, etc.)
PriceMath.round_tick(100.12)  # => 100.10
PriceMath.round_tick(100.13)  # => 100.15

# For technical calculations (keep as .round(2))
atr_value.round(2)            # => 15.67
rsi_value.round(2)            # => 45.23
```

## Migration Notes

- **Only** `.round(2)` calls on **DhanHQ API price values** have been replaced with `PriceMath.round_tick()`
- **Technical indicators and calculations** continue to use `.round(2)` for precision
- The module automatically handles nil values safely
- No breaking changes to existing functionality
- Performance impact is minimal (simple mathematical operations)

## Future Enhancements

1. **Dynamic Tick Sizes**: Support for different tick sizes per instrument type
2. **Batch Operations**: Optimize multiple price calculations
3. **Caching**: Cache frequently used tick calculations
4. **Validation**: Add more comprehensive price validation rules
