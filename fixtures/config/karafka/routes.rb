KarafkaApp.consumer_groups.draw do
  consumer_group :dummy_group do
    topic :test do
      consumer DummyConsumer
    end
  end
end
