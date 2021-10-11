# frozen_string_literal: true

require_relative 'redis_utility/version'
require 'yajl'
require 'json'
require 'multi_json'

# rubocop:disable Metrics/ModuleLength

# module RedisUtility namespace for redis methods
module RedisUtility
  extend self
  KEY_BATCH_SIZE = 1000

  # Imports a line-by-line json string
  def import_data(file)
    bzip2_openfile(file, 'rb') do |f1|
      until f1.eof?
        keys = 0
        redis.pipelined do
          # rubocop:disable Lint/AssignmentInCondition
          while curr_line = f1.gets
            # rubocop:enable Lint/AssignmentInCondition
            line = JSON.parse(curr_line)
            line.each do |key, val|
              keys += 1
              # first delete the record from the server before adding new value
              case val
              when Hash
                redis.del key
                redis.mapped_hmset(key, val)
              when Array
                redis.del key
                if val[0].is_a?(Array) && val[0][1].is_a?(Float) # zset
                  val = val.map { |v| [v[1], v[0]] }
                  redis.zadd(key, val)
                else
                  redis.rpush(key, val)
                end
              else
                redis.set(key, val)
              end
            end
            # Done with the line
            if keys > KEY_BATCH_SIZE
              print '.'
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
          keys = allkeys[nstart...nstart + KEY_BATCH_SIZE]
          types = redis.pipelined { keys.each { |k| redis.type(k) } }
          # print "Got types\n"
          string_keys = []
          pkeys = []
          pvals = redis.pipelined do
            keys.each_with_index do |key, idx|
              case types[idx]
              when 'string'
                string_keys << key
              when 'hash'
                pkeys << key
                redis.hgetall(key)
              when 'list'
                pkeys << key
                redis.lrange(key, 0, -1)
              when 'zset'
                pkeys << key
                redis.zrange(key, 0, -1, with_scores: true)
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

    value
  end

  def cache(key, params = {})
    expire = params[:expire]
    recalculate = params[:recalculate]

    if recalculate || (value = redis.get(key)).nil?
      value = MultiJson.encode(yield(self))

      redis.set(key, value)
      redis.expire(key, expire) if expire
    end

    MultiJson.decode(value)
  end

  def export_string_data(key_patterns, filename)
    key_patterns = [key_patterns] if key_patterns.is_a? String

    File.open(filename, 'w') do |f|
      key_patterns.each do |kp|
        keys = redis.keys(kp)
        write_string_keys(keys, f)
      end
    end
  end

  def redis
    unless @redis
      # print "RedisUtility: Connecting\n"
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

  #########################################
  private

  def quantity_with_unit(quantity, unit, unit_s = nil)
    "#{quantity} #{quantity > 1 ? (unit_s || "#{unit}s") : unit}"
  end

  def system_with_print(cmd)
    print "EXEC:#{cmd}\n"
    ret = system(cmd)
    print "EXEC failed\n" if ret.nil?
  end

  # Opens the bzip2 and yield with File object (file itself is opened)
  def bzip2_openfile(file_nm, mode, &block)
    raise 'Not implemented for writing bzip2 yet' if mode.include?('w')

    file_nm = file_nm.to_s
    if file_nm.end_with?('.bz2')
      raise "#{file_nm} does not exist" unless File.exist?(file_nm)

      file = file_nm[0..-5]
      File.delete(file) if File.exist?(file)
      system_with_print("bunzip2 -kd #{file_nm}")
    else
      file = file_nm
    end

    File.open(file, mode, &block)

    File.delete(file) if file_nm.end_with?('.bz2')
  end

  def write_string_keys_chunk(string_keys, file_obj)
    return unless string_keys.size.positive?

    hash = {}
    string_vals = redis.mget(string_keys)
    string_keys.each_with_index do |key, idx|
      val = string_vals[idx]
      next unless val
      next if key.start_with?('YMProd:rails_cache') # Migration to avoid legacy cache

      if val.nil?
        print "RedisUtility: Can not get value for key #{key}, skipped\n"
      else
        hash[key] = val
      end
    end
    Yajl::Encoder.encode(hash, file_obj)
    file_obj.write("\n")
  end

  WRITE_BATCH_SIZE = 100
  def write_string_keys(string_keys, file_obj)
    while string_keys.size > WRITE_BATCH_SIZE
      first_chunk = string_keys.shift(WRITE_BATCH_SIZE)
      write_string_keys_chunk(first_chunk, file_obj)
    end
    write_string_keys_chunk(string_keys, file_obj)
  end

  def write_pipelined_results(keys, vals, file_obj)
    keys.each_with_index do |key, idx|
      begin
        Yajl::Encoder.encode({ key => vals[idx] }, file_obj)
      rescue EncodingError
        print "Skipped #{key}. Encoding error\n"
      end
      file_obj.write("\n")
    end
  end
end

# rubocop:enable Metrics/ModuleLength
