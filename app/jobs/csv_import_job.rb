# frozen_string_literal: true

class CsvImportJob < ApplicationJob
  queue_as :default

  require 'open-uri'

  def perform(*_args)
    file_url = ENV.fetch('CSV_FILE_URL', nil)
    file_path = download_file(file_url)
    InstrumentsImporter.import(file_path)
    cleanup_file(file_path)
  end

  private

  # Downloads the file from the given URL
  def download_file(url = ENV.fetch('CSV_FILE_URL', nil))
    file_path = Rails.root.join('tmp/api-scrip-master-detailed.csv')
    File.write(file_path, URI.open(url).read)
    file_path
  end

  # Deletes the file after import
  def cleanup_file(file_path)
    FileUtils.rm_f(file_path)
  end
end
