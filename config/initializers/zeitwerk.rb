# frozen_string_literal: true

# Configure Zeitwerk to ignore the dhanhq directory
# This is a backwards-compatibility layer that defines Dhanhq::API
# (not Dhanhq::Api as Zeitwerk expects based on the file name)
Rails.autoloaders.main.ignore(Rails.root.join('lib/dhanhq'))

