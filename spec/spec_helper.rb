# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
end

require 'composer'
require 'webmock/rspec'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Suppress logging during tests
  config.before(:each) do
    @original_filter_level = Composer::Logger.filter_level
    Composer::Logger.filter_level = Composer::Severity::NONE
  end

  config.after(:each) do
    Composer::Logger.filter_level = @original_filter_level
  end
end

WebMock.disable_net_connect!(allow_localhost: true)
