namespace :csv do
  desc "Import instruments from CSV"
  task import: :environment do
    file_path = ENV["FILE_PATH"]
    raise "Please provide FILE_PATH as an environment variable" unless file_path

    CsvImporter.import(file_path)
    puts "CSV import completed successfully!"
  end
end
