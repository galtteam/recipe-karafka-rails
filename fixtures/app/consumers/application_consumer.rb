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
