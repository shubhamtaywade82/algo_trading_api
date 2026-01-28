# frozen_string_literal: true

require 'matrix'

module Indicators
  class AdaptiveSupertrend
    # Enhanced SuperTrend with Machine Learning Adaptive Parameters
    # Uses K-means clustering to optimize ATR multiplier dynamically

    # period           → ATR look-back period (default: 10)
    # base_multiplier  → Base ATR multiplier (default: 2.0)
    # training_period  → Number of periods for ML training (default: 50)
    # num_clusters     → Number of volatility clusters (default: 3)
    # performance_alpha → Learning rate for performance tracking (default: 0.1)
    def initialize(series:, period: 10, base_multiplier: 2.0, training_period: 50, num_clusters: 3, performance_alpha: 0.1)
      @series           = series
      @period           = period
      @base_multiplier  = base_multiplier
      @training_period  = training_period
      @num_clusters     = num_clusters
      @performance_alpha = performance_alpha

      # ML components
      @multiplier_candidates = [1.5, 2.0, 2.5, 3.0, 3.5] # Different multiplier options
      @performance_scores    = Hash.new(0.0)               # Performance tracking for each multiplier
      @volatility_clusters   = []                          # K-means clusters
      @adaptive_multipliers  = []                          # Array to store selected multipliers
    end

    def call
      highs  = @series.highs
      lows   = @series.lows
      closes = @series.closes

      return Array.new(closes.size) if closes.size < @training_period

      # Calculate ATR (Enhanced with ML adaptive period)
      atr = calculate_adaptive_atr(highs, lows, closes)

      # Perform volatility clustering and multiplier optimization
      adaptive_multipliers = optimize_multipliers_with_clustering(closes, atr)

      # Calculate SuperTrend with adaptive multipliers
      calculate_adaptive_supertrend(highs, lows, closes, atr, adaptive_multipliers)
    end

    private

    def calculate_adaptive_atr(highs, lows, closes)
      trs = highs.zip(lows, closes.each_cons(2).map(&:first).unshift(nil)).map do |h, l, prev_close|
        next nil unless prev_close

        [(h - l), (h - prev_close).abs, (l - prev_close).abs].max
      end

      atr = Array.new(closes.size)

      # Enhanced ATR with volatility regime adaptation
      closes.each_index do |i|
        if i == @period
          atr[i] = trs[1..@period].compact.sum / @period.to_f
        elsif i > @period
          # Adaptive smoothing based on volatility regime
          volatility_factor = calculate_volatility_factor(closes, i)
          adaptive_alpha = [0.05, 0.2 / (1 + volatility_factor)].max
          atr[i] = (adaptive_alpha * trs[i]) + ((1 - adaptive_alpha) * atr[i - 1])
        end
      end

      atr
    end

    def calculate_volatility_factor(closes, index)
      return 1.0 if index < 20

      # Calculate recent volatility vs historical average
      recent_returns = closes[(index - 19)..index].each_cons(2).map { |a, b| (b - a) / a }
      recent_vol = Math.sqrt(recent_returns.sum { |r| r * r } / recent_returns.size)

      historical_returns = closes[[(index - 100), 0].max..index].each_cons(2).map { |a, b| (b - a) / a }
      historical_vol = Math.sqrt(historical_returns.sum { |r| r * r } / historical_returns.size)

      recent_vol / (historical_vol + 1e-8)
    end

    def optimize_multipliers_with_clustering(closes, atr)
      adaptive_multipliers = Array.new(closes.size, @base_multiplier)

      (@training_period...closes.size).each do |i|
        # Extract features for clustering (volatility measures)
        features = extract_volatility_features(closes, atr, i)
        next if features.empty?

        # Perform K-means clustering on volatility features
        cluster_assignment = perform_kmeans_clustering(features)

        # Select optimal multiplier based on cluster and performance
        optimal_multiplier = select_optimal_multiplier(cluster_assignment, i, closes, atr)
        adaptive_multipliers[i] = optimal_multiplier

        # Update performance scores
        update_performance_scores(i, closes, atr, adaptive_multipliers[i])
      end

      adaptive_multipliers
    end

    def extract_volatility_features(closes, atr, current_index)
      return [] if current_index < @period + 10

      lookback_start = [current_index - @training_period, @period].max
      features = []

      (lookback_start...current_index).each do |i|
        next if atr[i].nil?

        # Feature 1: Normalized ATR
        avg_atr = atr[lookback_start...current_index].compact.sum / (current_index - lookback_start)
        normalized_atr = atr[i] / (avg_atr + 1e-8)

        # Feature 2: Price volatility (rolling std of returns)
        if i >= 10
          recent_returns = closes[(i - 9)..i].each_cons(2).map { |a, b| (b - a) / a }
          volatility = Math.sqrt(recent_returns.sum { |r| r * r } / recent_returns.size)
        else
          volatility = 0.0
        end

        # Feature 3: Trend strength (price vs moving average)
        ma_period = [10, i].min
        moving_avg = closes[(i - ma_period + 1)..i].sum / ma_period.to_f
        trend_strength = (closes[i] - moving_avg) / moving_avg

        features << [normalized_atr, volatility * 100, trend_strength * 100]
      end

      features
    end

    def perform_kmeans_clustering(features)
      return 0 if features.empty?

      # Simple K-means implementation for volatility clustering
      k = [@num_clusters, features.size].min
      return 0 if k <= 1

      # Initialize centroids randomly
      centroids = features.sample(k)
      max_iterations = 20

      max_iterations.times do
        # Assign points to closest centroid
        assignments = features.map do |point|
          distances = centroids.map { |centroid| euclidean_distance(point, centroid) }
          distances.index(distances.min)
        end

        # Update centroids
        new_centroids = []
        k.times do |cluster|
          cluster_points = assignments.each_with_index.select { |assignment, _| assignment == cluster }.map { |_, index| features[index] }
          if cluster_points.empty?
            new_centroids << centroids[cluster]
          else
            # Calculate mean of cluster points
            mean_point = []
            cluster_points.first.size.times do |dim|
              mean_point << (cluster_points.pluck(dim).sum / cluster_points.size.to_f)
            end
            new_centroids << mean_point
          end
        end

        # Check for convergence
        converged = centroids.zip(new_centroids).all? do |old, new|
          euclidean_distance(old, new) < 0.001
        end

        centroids = new_centroids
        break if converged
      end

      # Return cluster assignment for the most recent feature
      return 0 if features.empty?

      distances = centroids.map { |centroid| euclidean_distance(features.last, centroid) }
      distances.index(distances.min)
    end

    def euclidean_distance(point1, point2)
      Math.sqrt(point1.zip(point2).sum { |a, b| (a - b)**2 })
    end

    def select_optimal_multiplier(cluster_assignment, _current_index, _closes, _atr)
      # Map clusters to volatility regimes and select appropriate multipliers
      candidate_multipliers = case cluster_assignment
                              when 0  # Low volatility cluster
                                [2.0, 2.5]
                              when 1  # Medium volatility cluster
                                [2.5, 3.0]
                              when 2  # High volatility cluster
                                [3.0, 3.5]
                              else
                                [@base_multiplier]
                              end

      # Select best performing multiplier from candidates
      best_multiplier = candidate_multipliers.max_by { |mult| @performance_scores[mult] }
      best_multiplier || @base_multiplier
    end

    def update_performance_scores(current_index, closes, atr, used_multiplier)
      return if current_index < @period + 5

      # Calculate performance based on trend accuracy over last 5 periods
      lookback = 5
      start_idx = current_index - lookback

      # Simulate SuperTrend signal with this multiplier
      correct_signals = 0
      total_signals = 0

      (start_idx...current_index).each do |i|
        next if atr[i].nil?

        # Calculate what the SuperTrend signal would have been
        mid = (@series.highs[i] + @series.lows[i]) / 2.0
        upper_band = mid + (used_multiplier * atr[i])
        lower_band = mid - (used_multiplier * atr[i])

        # Determine if signal was correct (simplified)
        if closes[i] > upper_band && closes[i + 1] && closes[i + 1] > closes[i]
          correct_signals += 1
        elsif closes[i] < lower_band && closes[i + 1] && closes[i + 1] < closes[i]
          correct_signals += 1
        end

        total_signals += 1
      end

      # Update performance score with exponential smoothing
      return unless total_signals.positive?

      accuracy = correct_signals.to_f / total_signals
      @performance_scores[used_multiplier] =
        ((1 - @performance_alpha) * @performance_scores[used_multiplier]) +
        (@performance_alpha * accuracy)
    end

    def calculate_adaptive_supertrend(highs, lows, closes, atr, adaptive_multipliers)
      upperband = Array.new(closes.size)
      lowerband = Array.new(closes.size)
      supertrend = Array.new(closes.size)

      closes.each_index do |i|
        next if atr[i].nil? || adaptive_multipliers[i].nil?

        mid = (highs[i] + lows[i]) / 2.0
        multiplier = adaptive_multipliers[i]

        upperband[i] = mid + (multiplier * atr[i])
        lowerband[i] = mid - (multiplier * atr[i])
      end

      # Apply SuperTrend logic with adaptive bands
      (0...closes.size).each do |i|
        next if atr[i].nil?

        if i == @period
          supertrend[i] = closes[i] <= upperband[i] ? upperband[i] : lowerband[i]
          next
        end

        supertrend[i] = if supertrend[i - 1] == upperband[i - 1]
                          if closes[i] <= upperband[i]
                            [upperband[i], supertrend[i - 1]].min
                          else
                            lowerband[i]
                          end
                        elsif closes[i] >= lowerband[i]
                          [lowerband[i], supertrend[i - 1]].max
                        else
                          upperband[i]
                        end
      end

      supertrend
    end

    # Additional helper methods for enhanced functionality

    def get_current_volatility_regime(index)
      return :unknown if index < @training_period

      features = extract_volatility_features(@series.closes, calculate_adaptive_atr(@series.highs, @series.lows, @series.closes), index)
      return :unknown if features.empty?

      cluster = perform_kmeans_clustering([features.last])

      case cluster
      when 0 then :low
      when 1 then :medium
      when 2 then :high
      else :unknown
      end
    end

    def get_performance_metrics
      {
        multiplier_scores: @performance_scores,
        total_clusters: @num_clusters,
        training_period: @training_period
      }
    end

    def get_adaptive_multiplier(index)
      @adaptive_multipliers[index] || @base_multiplier
    end
  end
end