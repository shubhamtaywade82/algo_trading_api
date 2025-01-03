class CsvImportJob < ApplicationJob
  queue_as :default

  require "open-uri"

  def perform(*args)
    file_path = download_file(file_url)
    CsvImporter.import(file_path)
    cleanup_file(file_path)
  end

  private

  # Downloads the file from the given URL
  def download_file(url = ENV["CSV_FILE_URL"])
    file_path = Rails.root.join("tmp", "api-scrip-master-detailed.csv")
    File.write(file_path, URI.open(url).read)
    file_path
  end

  # Deletes the file after import
  def cleanup_file(file_path)
    File.delete(file_path) if File.exist?(file_path)
  end
end
