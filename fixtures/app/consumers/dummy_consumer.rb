class DummyConsumer < ApplicationConsumer
  def consume
    Karafka.logger.info params.raw_payload
  end
end
