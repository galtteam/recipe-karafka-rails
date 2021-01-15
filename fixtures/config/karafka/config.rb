KarafkaApp.setup do |config|
  config.kafka.seed_brokers = ENV['KAFKA_SEED_BROKERS'].present? ? ENV['KAFKA_SEED_BROKERS'].split(',') : %w[kafka://127.0.0.1:9092]
  config.client_id = 'service_name'
  config.logger = Rails.logger
end
