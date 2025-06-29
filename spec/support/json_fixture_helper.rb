module JsonFixtureHelper
  def json_fixture(name)
    file = Rails.root.join("spec/fixtures/alerts/#{name}.json")
    JSON.parse(File.read(file)).deep_symbolize_keys
  end

  def data_fixture(name)
    file = Rails.root.join("spec/fixtures/data/#{name}.json")
    JSON.parse(File.read(file)).deep_symbolize_keys
  end
end