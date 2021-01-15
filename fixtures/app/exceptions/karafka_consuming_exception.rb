class KarafkaConsumingException < StandardError
  attr_reader :original_exception, :params, :params_batch

  def initialize(original_exception, params, params_batch)
    @original_exception, @params, @params_batch = original_exception, params, params_batch
    super(original_exception.message)
  end
end
