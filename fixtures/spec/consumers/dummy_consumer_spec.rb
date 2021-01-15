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
