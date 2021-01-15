ensure_changes_commited!

copy_fixture 'karafka.rb'
copy_fixture 'config/karafka/config.rb'
copy_fixture 'config/karafka/routes.rb'

copy_fixture 'app/exceptions/karafka_consuming_exception.rb'
copy_fixture 'app/services/karafka_exception_listener.rb'

copy_fixture 'app/consumers/application_consumer.rb'
copy_fixture 'app/consumers/dummy_consumer.rb'

copy_fixture 'spec/karafka_helper.rb'
copy_fixture 'spec/support/karafka.rb'
copy_fixture 'spec/consumers/dummy_consumer_spec.rb'

file 'Gemfile' do
  put_to_end "gem 'karafka'"

  test_gems = <<~TST
    gem 'karafka-testing'
  TST

  indent 2 do
    put_after_line test_gems, "group :test do"
  end
end

run %Q{bundle install}

puts "Warning! You have to implement your own notification service inside app/services/karafka_exception_listener.rb"
