FactoryBot.define do
  factory :margin_requirement do
    instrument
    buy_co_min_margin_per { 20.0 }
    sell_co_min_margin_per { 20.0 }
    buy_bo_min_margin_per { 10.0 }
    sell_bo_min_margin_per { 10.0 }
    buy_co_sl_range_max_perc { 1.0 }
    sell_co_sl_range_max_perc { 1.0 }
    buy_co_sl_range_min_perc { 0.5 }
    sell_co_sl_range_min_perc { 0.5 }
    buy_bo_sl_range_max_perc { 1.5 }
    sell_bo_sl_range_max_perc { 1.5 }
    buy_bo_sl_range_min_perc { 0.5 }
    sell_bo_sl_min_range { 0.5 }
    buy_bo_profit_range_max_perc { 5.0 }
    sell_bo_profit_range_max_perc { 5.0 }
    buy_bo_profit_range_min_perc { 1.0 }
    sell_bo_profit_range_min_perc { 1.0 }
  end
end
