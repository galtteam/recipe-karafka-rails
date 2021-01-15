# Consuming Kafka messages

This tutorial will provide you step by step instructions for consuming the Apache Kafka messages from your rails app

## The Apache Kafka local broker with docker

```
git clone https://github.com/wurstmeister/kafka-docker.git
cd kafka-docker
git checkout 1.0.1
vim docker-compose-single-broker.yml
# Replace as followed:
# KAFKA_ADVERTISED_HOST_NAME: 192.168.99.100
# set to:
# KAFKA_ADVERTISED_HOST_NAME: 127.0.0.01
docker-compose -f docker-compose-single-broker.yml up
```

## The Karafka Installation

```ruby
gem 'karafka'

group :test do
  gem 'karafka-testing'
end
```

Then run `bundle install`

The official Karafka documentation suggests using its own generator `bundle exec karafka install`. Please avoid it and use the config files provided below

### Basic configuration

1. **Create the folder for the karafka configs**

`mkdir -p config/karafka`

2. **Create the `config/karafka/config.rb`**

```ruby
KarafkaApp.setup do |config|
  config.kafka.seed_brokers = %w[kafka://127.0.0.1:9092]
  config.client_id = 'service_name'
  config.logger = Rails.logger
end
```

3. **Create the `config/karafka/routes.rb`**

```ruby
KarafkaApp.consumer_groups.draw do
  consumer_group :dummy_group do
    topic :test do
      consumer DummyConsumer
    end
  end
end
```

4. **Connect with the exception handling system**

We need a small workaround to get more data in the Airbrake when consuming failed.

**Important note: The code below wasn't tested with the real Airbrake server.**

a. Create a folder for exceptions `mkdir -p app/exceptions`
b. Create an exception container `app/exceptions/karafka_consuming_exception.rb`

```ruby
class KarafkaConsumingException < StandardError
  attr_reader :original_exception, :params, :params_batch

  def initialize(original_exception, params, params_batch)
    @original_exception, @params, @params_batch = original_exception, params, params_batch
    super(original_exception.message)
  end
end
```

c. Add the `KarafkaAirbrakeListener` module to someplace where rails can find it.

```ruby
# frozen_string_literal: true

# Example Airbrake/Errbit listener for error only notifications upon Karafka problems
module KarafkaAirbrakeListener
  # Postfixes of things that we need to log
  PROBLEM_POSTFIXES = %w[
    _error
    _retry
  ].freeze

  class << self
    # All the events in which something went wrong trigger the *_error
    # method, so we can catch all of them and notify Airbrake about that.
    #
    # @param method_name [Symbol] name of a method we want to run
    # @param args [Array] arguments of this method
    # @param block [Proc] additional block of this method
    def method_missing(method_name, *args, &block)
      return super unless eligible?(method_name)

      exception = args.last[:error]

      if exception.is_a?(KarafkaConsumingException)
        Airbrake.notify exception.original_exception, params: exception.params, params_batch: exception.params_batch
      else
        Airbrake.notify exception
      end
    rescue StandardError => e
      Airbrake.notify e
    end

    # @param method_name [Symbol] name of a method we want to run
    # @return [Boolean] true if we respond to this missing method
    def respond_to_missing?(method_name, include_private = false)
      eligible?(method_name) || super
    end

    private

    # @param method_name [Symbol] name of invoked method
    # @return [Boolean] true if we are supposed to do something with
    #   a given method execution
    def eligible?(method_name)
      PROBLEM_POSTFIXES.any? do |postfix|
        method_name.to_s.end_with?(postfix)
      end
    end
  end
end
```

5. **Create the main karafka file `Rails root/karafka.rb`**

```ruby
# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'development'
ENV['KARAFKA_ENV'] = ENV['RAILS_ENV']
require ::File.expand_path('config/environment', __dir__)
Rails.application.eager_load!

# These lines will make Karafka print to stdout like puma or unicorn
if Rails.env.development?
  Rails.logger.extend(
    ActiveSupport::Logger.broadcast(
      ActiveSupport::Logger.new($stdout)
    )
  )

  Karafka.monitor.subscribe(
    Karafka::CodeReloader.new(
      *Rails.application.reloaders
    )
  )
end

class KarafkaApp < Karafka::App
  # Comment out this part if you are not using instrumentation and/or you are not
  # interested in logging events for certain environments. Since instrumentation
  # notifications add extra boilerplate if you want to achieve max performance,
  # listen to only what you really need for given environment.
  Karafka.monitor.subscribe(WaterDrop::Instrumentation::StdoutListener.new)
  Karafka.monitor.subscribe(Karafka::Instrumentation::StdoutListener.new)
  Karafka.monitor.subscribe(Karafka::Instrumentation::ProctitleListener.new)

  Karafka.monitor.subscribe(KarafkaAirbrakeListener) if Rails.env.production?
end

require './config/karafka/config'
require './config/karafka/routes'

KarafkaApp.boot!
```

6. **The Rails integration**

The original documentation suggest to add the `require Rails.root.join(Karafka.boot_file)` code to the END of `config/environment.rb` file. However, I didn't find any reason to do this besides making tests work. So I've skipped that part and added my workaround for tests. Maybe it could be useful for the WaterDrop which we are not going to use now.

As the result, this line will just validate the Karafka config and nothing else, but I would like to avoid it for two reasons:

1. It will require to add all the karafka ENV variables for the Rails server pods
2. It will add a confusing message that looks like karafka was run within the webserver process. But it's not

Confirmed here https://github.com/karafka/karafka/issues/645

### Starting the consuming process

To start the karafka server you will need to define at least a single consumer subscribed to some topic.

In this example, we will provide the `DummyConsumer` code which should be replaced with the real one.

1. Create a folder for all consumers

`mkdir -p app/consumers`

2. Create the basic consumer `app/consumers/application_consumer.rb`

```ruby
# frozen_string_literal: true

# Application consumer from which all Karafka consumers should inherit
# You can rename it if it would conflict with your current code base (in case you're integrating
# Karafka with other frameworks)
class ApplicationConsumer < Karafka::BaseConsumer
  def call
    was_tried_to_recover_db_connections = false
    begin
      super
    rescue ActiveRecord::StatementInvalid => e
      raise e if was_tried_to_recover_db_connections

      ::ActiveRecord::Base.clear_active_connections!
      was_tried_to_recover_db_connections = true
      retry
    rescue StandardError => e
      raise KarafkaConsumingException.new(e, params.to_json, params_batch.to_json)
    end
  end
end
```

This code will handle the Db connections from lost. More information here https://github.com/karafka/karafka/wiki/Problems-and-Troubleshooting#why-karafka-does-not-restart-dead-pg-connections


3. Create the dummy consumer `app/consumers/dummy_consumer.rb`

```ruby
class DummyConsumer < ApplicationConsumer
  def consume
    Karafka.logger.info params.raw_payload
  end
end
```

4. Run the Karafka server

`bundle exec karafka server`

### Ensure messages processing

TODO: Add an example here with producing and consuming when KafkaNotifier will be finished

### Setup for rspec

1. Add a separate rspec helper for the karafka `spec/karafka_helper.rb`

```ruby
require 'rails_helper'
require Rails.root.join(Karafka.boot_file)
```

2. Add the `spec/support/karafka.rb` file.

```ruby
require 'karafka/testing/rspec/helpers'

RSpec.configure do |config|
  config.include Karafka::Testing::RSpec::Helpers
end
```

3. Create a folder for the consumer's specs

`mkdir -p spec/consumers`

4. Add a dummy consumer spec `spec/consumers/dummy_consumer_spec.rb`

```ruby
require 'karafka_helper'

RSpec.describe DummyConsumer do
  # This will create a consumer instance with all the settings defined for the given topic
  subject(:consumer) { karafka_consumer_for(:test) }

  before do
    publish_for_karafka('test_message 1')
  end

  it 'expects to log a proper message' do
    expect(Karafka.logger).to receive(:info).with('test_message 1')
    consumer.consume
  end
end
```

A few notes to the spec example
1. You should always use the `karafka_consumer_for` inside the `subject` block. It will use the rspec subject as a state handler.
2. The `karafka_consumer_for` will check if topic exists and just create a consumer instance `described_class.new(selected_topic)`
3. The `publish_for_karafka` method will put data into the subject. This is why point 1 is important
4. You can call the `publish_for_karafka` method several times to emulate the batch processing

### Deployment

**Important Notes:**

1. The new process should be started only when the previous one died. https://github.com/zendesk/racecar#deploying-to-kubernetes
2. Usually you will need just a single consumer group per application. However, if you need more than you should also ensure that you have enough DB connections. This number should be not less than the consumer group's count.
3. You should set up the `kafka.heartbeat_interval` according to your Kafka config
4. That heartbeat interval from the previous point works at the same thread with the fetching logic. So you should ensure that you fetch data fast, or increase the Kafka session timeout.
