# RedisUtility

An awesome gem which provides utility methods for redis db. Can be used with any rails application which is using redis.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'redis_utility'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install redis_utility

## Usage

After installing the gem create a file redis_utility.rb in config/initializers with following content:

```ruby
RedisUtility.redis_config = { host: 'localhost', timeout: 60, db: 'redis_db', password: 'password'}
```

Following are use cases:

### To get the redis config
```ruby
RedisUtility.redis
```

### To stop and create a new redis connection
```ruby
RedisUtility.reconnect
```

### To import data from a file to redis
```ruby
RedisUtility.import_data('import_file.ljson')
```

### To export matching keys values from redis to a file
```ruby
RedisUtility.export_data('Car_Acura|CL|*', 'ouput_export_file.ljson')
```

### To cache a string to redis db. It caches the value of the block passed to it
```ruby
RedisUtility.cache_string('cache_this', { expire: 20 }) { 'the value of block passed' }
```

### To cache multijson value in redis. It caches the value of the block passed to it
```ruby
RedisUtility.cache('cache_multi_json', { expire: 20 }) { '{"Car_Acura|CL|":"01010000_EE000000000","Car_Acura|CL|L4-2.2L":"01010100_2000000000"}' }
```

### To export matching string key data to a file
```ruby
RedisUtility.export_string_data('Car_Acura|CL|*', 'string_export_file.ljson')
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/redis_utility. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/redis_utility/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the RedisUtility project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/redis_utility/blob/master/CODE_OF_CONDUCT.md).
