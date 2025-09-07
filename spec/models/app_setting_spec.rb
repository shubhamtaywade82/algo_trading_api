require 'rails_helper'

RSpec.describe AppSetting, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:key) }
    it { should validate_presence_of(:value) }
  end

  describe 'primary key' do
    it 'uses key as primary key' do
      expect(AppSetting.primary_key).to eq('key')
    end
  end

  describe '[] and []= methods' do
    it 'can set and get values using hash syntax' do
      AppSetting['test_key'] = 'test_value'
      expect(AppSetting['test_key']).to eq('test_value')
    end

    it 'updates existing key instead of creating duplicate' do
      AppSetting['test_key'] = 'initial_value'
      AppSetting['test_key'] = 'updated_value'

      expect(AppSetting.count).to eq(1)
      expect(AppSetting['test_key']).to eq('updated_value')
    end

    it 'converts key to string' do
      AppSetting[:symbol_key] = 'test'
      expect(AppSetting['symbol_key']).to eq('test')
    end
  end

  describe 'fetch_bool' do
    before do
      AppSetting['test_bool'] = 'true'
      ENV['TEST_BOOL_ENV'] = 'false'
    end

    after do
      ENV.delete('TEST_BOOL_ENV')
    end

    it 'returns boolean value from database' do
      expect(AppSetting.fetch_bool('test_bool')).to be true
    end

    it 'falls back to ENV variable' do
      AppSetting.where(key: 'test_bool').delete_all
      expect(AppSetting.fetch_bool('test_bool_env')).to be false
    end

    it 'uses default when neither database nor ENV has value' do
      expect(AppSetting.fetch_bool('nonexistent', default: true)).to be true
      expect(AppSetting.fetch_bool('nonexistent', default: false)).to be false
    end
  end

  describe 'fetch_float' do
    before do
      AppSetting['test_float'] = '1.5'
      ENV['TEST_FLOAT_ENV'] = '2.5'
    end

    after do
      ENV.delete('TEST_FLOAT_ENV')
    end

    it 'returns float value from database' do
      expect(AppSetting.fetch_float('test_float', default: 0.0)).to eq(1.5)
    end

    it 'falls back to ENV variable' do
      AppSetting.where(key: 'test_float').delete_all
      expect(AppSetting.fetch_float('test_float_env', default: 0.0)).to eq(2.5)
    end

    it 'uses default when neither database nor ENV has value' do
      expect(AppSetting.fetch_float('nonexistent', default: 3.14)).to eq(3.14)
    end
  end

  describe 'fetch_int' do
    before do
      AppSetting['test_int'] = '42'
      ENV['TEST_INT_ENV'] = '100'
    end

    after do
      ENV.delete('TEST_INT_ENV')
    end

    it 'returns integer value from database' do
      expect(AppSetting.fetch_int('test_int', default: 0)).to eq(42)
    end

    it 'falls back to ENV variable' do
      AppSetting.where(key: 'test_int').delete_all
      expect(AppSetting.fetch_int('test_int_env', default: 0)).to eq(100)
    end

    it 'uses default when neither database nor ENV has value' do
      expect(AppSetting.fetch_int('nonexistent', default: 999)).to eq(999)
    end
  end
end
