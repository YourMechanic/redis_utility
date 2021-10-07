# frozen_string_literal: true

require_relative 'redis_utility/version'
require 'yajl'

module RedisUtility
  extend self
  KEY_BATCH_SIZE = 1000

  # Imports a line-by-line json string
  def import_data(file)
    bzip2_openfile(file, 'rb') do |f1|
      while !f1.eof? do
        keys = 0
        redis.pipelined do
          while curr_line = f1.gets
            line = JSON.parse(curr_line)
            line.each do |_key, _val|
              keys += 1
              # first delete the record from the server before adding new value
              case _val
              when Hash
                redis.del _key
                redis.mapped_hmset(_key, _val)
              when Array
                if _val[0].is_a?(Array) && _val[0][1].is_a?(Float) # zset
                  redis.del _key
                  _val = _val.map { |v| [v[1], v[0]] }
                  redis.zadd(_key, _val)
                else
                  redis.del _key
                  redis.rpush(_key, _val)
                end
              else
                redis.set(_key, _val)
              end
            end
            # Done with the line
            if keys > KEY_BATCH_SIZE
              print "."
              break
            end
          end
        end
      end
    end
  end

  # Export the key pattern
  def export_data(key_patterns, filename)
    key_patterns = [key_patterns] if key_patterns.is_a? String

    File.open(filename, 'w+b') do |f|
      key_patterns.each do |kp|
        allkeys = kp.include?('*') ? redis.keys(kp).sort : [kp]
        print "Working on #{kp}: #{quantity_with_unit(allkeys.size, 'key')}\n"
        nstart = 0
        while nstart < allkeys.size
          keys = allkeys[nstart...nstart+KEY_BATCH_SIZE]
          types = redis.pipelined { keys.each { |k| redis.type(k) } }
          #print "Got types\n"
          string_keys = []
          pkeys = []
          pvals = redis.pipelined do
            keys.each_with_index do |key, idx|
              case types[idx]
              when 'string'
                string_keys << key
              when 'hash'
                pkeys << key
                val = redis.hgetall(key)
              when 'list'
                pkeys << key
                val = redis.lrange(key, 0, -1)
              when 'zset'
                pkeys << key
                val = redis.zrange(key, 0, -1, :with_scores=>true)
              else
                print "RedisUtility: Can not deal with #{types[idx]} for key #{key}, skipped\n"
              end
            end
          end
          write_pipelined_results(pkeys, pvals, f)
          write_string_keys(string_keys, f)
          nstart += KEY_BATCH_SIZE
          print '.' if nstart < allkeys.size
        end
      end
    end
  end

  def cache_string(key, params = {})
    expire = params[:expire]
    recalculate = params[:recalculate]

    if recalculate || (value = redis.get(key)).nil?
      value = yield(self).to_s

      redis.set(key, value)
      redis.expire(key, expire) if expire
    end

    return value
  end

  def cache(key, params = {})
    expire = params[:expire]
    recalculate = params[:recalculate]

    if recalculate || (value = redis.get(key)).nil?
      value = MultiJson.encode(yield(self))

      redis.set(key, value)
      redis.expire(key, expire) if expire
    end

    return MultiJson.decode(value)
  end

  def export_string_data(key_patterns, filename)
    key_patterns = [key_patterns] if key_patterns.is_a? String

    File.open(filename, 'w') do |f|
      string_keys = []
      key_patterns.each do |kp|
        keys = redis.keys(kp)
        write_string_keys(keys, f)
      end
    end
  end

  def save_dynamic(opts = {})
    patterns = []
    if opts[:save_all]
      patterns << '*'
    else
      patterns << REDIS_PREFIX + '*'
      patterns << 'CachedSeo:*'
      patterns << 'SEO:SchedMaint:*'
      patterns << '*Auth@*' if opts[:save_sessions]
    end
    file = opts[:file_path] || dynamic_location
    export_data(patterns, file)
  end

  def load_dynamic(opts = {})
    file = opts[:file_path] || dynamic_location
    import_data(file) if File.exists?(file)
  end

  def redis
    if !@redis
      #print "RedisUtility: Connecting\n"
      cfg = REDIS_CONFIG.dup
      cfg[:timeout] = 60 # Set longer timeout for efficient bulk loading/save
      @redis = Redis.new(cfg)
    end
    @redis
  end

  def reconnect
    if @redis
      @redis._client.disconnect
      @redis = nil
      redis # This reconnects to redis with right configurations
    end
    nil
  end

  def rebuild_all_redis_keys(opts = {})
    save_dynamic(opts) unless opts[:no_save]
    redis.flushdb
    CarAttribute.import(true)
    CarMaintenance.import(true)
    load_dynamic(opts) unless opts[:no_save]
  end

  
  #########################################
  private

  def quantity_with_unit(q, u, us = nil)
    return q.to_s + ' ' + (q > 1 ? (us || (u + 's')) : u)
  end

  def system_with_print(cmd)
    print "EXEC:#{cmd}\n"
    ret = system(cmd)
    print "EXEC failed\n" if ret == nil
  end

  # Opens the bzip2 and yield with File object (file itself is opened)
  def bzip2_openfile(s, mode)
    raise "Not implemented for writing bzip2 yet" if mode.include?('w')
    s = s.to_s
    if (s.end_with?('.bz2'))
      raise "#{s} does not exist" unless File.exists?(s)
      file = s[0..-5]
      File.delete(file) if File.exists?(file)
      system_with_print("bunzip2 -kd #{s}")
    else
      file = s
    end

    File.open(file, mode) { |f| yield(f) }

    File.delete(file) if (s.end_with?('.bz2'))
  end

  def dynamic_location
    FileUtils.mkpath(CASA_ROOT.join('depot', Rails.env))
    CASA_ROOT.join('depot', Rails.env, 'redis_dynamic.json')
  end

  def write_string_keys_chunk(string_keys, f)
    if string_keys.size > 0
      hash = {}
      string_vals = redis.mget(string_keys)
      string_keys.each_with_index do |key, idx|
        val = string_vals[idx]
        ;next unless val
        ;next if key.start_with?('YMProd:rails_cache') # Migration to avoid legacy cache
        if val == nil
          print "RedisUtility: Can not get value for key #{key}, skipped\n"
        else
          hash[key] = val
        end
      end
      Yajl::Encoder.encode(hash, f)
      f.write("\n")
    end
  end

  WRITE_BATCH_SIZE = 100
  def write_string_keys(string_keys, f)
    while string_keys.size > WRITE_BATCH_SIZE
      first_chunk = string_keys.shift(WRITE_BATCH_SIZE)
      write_string_keys_chunk(first_chunk, f)
    end
    write_string_keys_chunk(string_keys, f)
  end

  def write_pipelined_results(keys, vals, f)
    keys.each_with_index do |key, idx|
      begin
        Yajl::Encoder.encode({key=>vals[idx]}, f)
      rescue EncodingError
        print "Skipped #{key}. Encoding error\n"
      end
      f.write("\n")
    end
  end
end
