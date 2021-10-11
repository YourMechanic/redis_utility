# frozen_string_literal: true

RSpec.describe RedisUtility do
  let(:import_file) { 'spec/upload_this.ljson' }
  let(:ouput_export_file) { 'spec/exported.ljson' }

  it 'has a version number' do
    expect(RedisUtility::VERSION).not_to be nil
  end

  it 'has a current db' do
    expect(Redis.current).to be
  end

  describe '.import_data' do
    it 'imports data from a file to redis' do
      RedisUtility.import_data(import_file)
      expect(RedisUtility.redis.get('Car_Acura|CL|')).to be
    end
  end

  describe '.export_data' do
    it 'exports matching keys from redis to a file' do
      RedisUtility.export_data('Car_Acura|CL|*', ouput_export_file)
      expect(File.exist?(ouput_export_file)).to be
    end
  end

  describe '.cache_string' do
    it 'caches a string to redis db' do
      RedisUtility.cache_string('cache_this', { expire: 20 }) { 'the value of block passed' }
      expect(RedisUtility.redis.get('cache_this')).to eq('the value of block passed')
    end
  end

  describe '.cache' do
    let(:multi_json) { '{"Car_Acura|CL|":"01010000_EE000000000","Car_Acura|CL|L4-2.2L":"01010100_2000000000"}' }
    it 'caches multijson value in redis' do
      expect(RedisUtility.cache('cache_multi_json', { expire: 20 }) { multi_json }).to eq(multi_json)
    end
  end

  describe '.export_string_data' do
    let(:string_export_file) { 'spec/exported_file.ljson' }
    it 'exports string data to a file' do
      RedisUtility.export_string_data('Car_Acura|CL|*', string_export_file)
      expect(File.exist?(string_export_file)).to be
    end
  end

  describe '.redis' do
    it 'returns a redis connection' do
      expect(RedisUtility.redis).to be
    end
  end

  describe '.reconnect' do
    it 'returns a new redis connection' do
      expect(RedisUtility.reconnect).to be_nil
    end
  end
end
