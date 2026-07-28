# frozen_string_literal: true

require_relative "base"

module ArchitectureGate
  module Checks
    class FloatMoney < Base
      MONEY_FIELDS = %w[price pnl margin amount cost fee premium strike].freeze

      def run(paths)
        forbidden_paths = @config.float_money_forbidden_in
        allowed_paths = @config.float_money_allowed_in

        forbidden_paths.each do |path_pattern|
          files = Dir.glob(path_pattern).select { |f| File.file?(f) }
          files.each do |file|
            next if allowed_paths.any? { |a| file.start_with?(a.gsub("/**", "")) }
            check_file(file)
          end
        end
      end

      private

      def check_file(file)
        content = File.read(file)
        lines = content.lines

        lines.each_with_index do |line, idx|
          next if line.strip.start_with?("#")

          if line.match?(/(#{MONEY_FIELDS.join('|')}).*\.to_f/i)
            @report.add_failure(
              check: "float_money",
              file: file,
              line: idx + 1,
              message: "Float conversion on money field: #{line.strip}",
              severity: :error
            )
          end

          if line.match?(/Float\(/)
            @report.add_failure(
              check: "float_money",
              file: file,
              line: idx + 1,
              message: "Float() call in domain/service layer: #{line.strip}",
              severity: :error
            )
          end
        end
      end
    end
  end
end
