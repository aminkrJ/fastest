require 'rubygems'
require 'capybara/poltergeist'
require 'capybara/rspec'

# This file is copied to spec/ when you run 'rails generate rspec:install'
ENV["RAILS_ENV"] = 'test'
RAILS_ENV = 'test'

require File.expand_path("../../config/environment", __FILE__)
require 'rspec/rails'

require "authlogic/test_case"
include Authlogic::TestCase

require 'email_spec'
require 'valid_attribute'

require 'savon/mock/spec_helper'

require 'webmock/rspec'

# Requires supporting ruby files with custom matchers and macros, etc,
# in spec/support/ and its subdirectories.
Dir[Rails.root.join("spec/support/**/*.rb")].each {|f| require f}

Capybara.register_driver :selenium_chrome do |app|
  # Linux and OSX Maverick doesn't support chrome driver for the moment
  if RUBY_PLATFORM.include?('linux') || `uname -r` =~ /^13/
    Capybara::Selenium::Driver.new(app, :browser => :firefox)
  else
    Capybara::Selenium::Driver.new(app, :browser => :chrome)
  end
end

Capybara.register_driver :chrome do |app|
  Capybara::Selenium::Driver.new(app, :browser => :chrome)
end

Capybara.register_driver :poltergeist_debug do |app|
  Capybara::Poltergeist::Driver.new(app, :debug => true)
end

Capybara.register_driver :poltergeist_no_js_errors do |app|
  Capybara::Poltergeist::Driver.new(app, :js_errors => false)
end

Capybara.javascript_driver = :poltergeist

Capybara.default_wait_time = 10

# Path for Savon Fixture
# Savon::Spec::Fixture.path = File.expand_path(Rails.root.join('spec', 'fixtures'))

RSpec.configure do |config|
  config.treat_symbols_as_metadata_keys_with_true_values = true
  config.filter_run :focus => true

  config.run_all_when_everything_filtered = true

  config.include FactoryGirl::Syntax::Methods
  config.include Savon::SpecHelper
  config.include Capybara::DSL
  config.include UserHelper
  config.include BookingEngineHelper
  config.include WaitForAjax

  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_path = "#{Rails.root}/spec/fixtures"

  config.global_fixtures = :site_settings

  config.mock_with :mocha

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, remove the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = false

  config.include(EmailSpec::Helpers)
  config.include(EmailSpec::Matchers)
end

# This code will be run each time you run your specs.
FactoryGirl.reload
WebMock.allow_net_connect!

RSpec.configure do |config|
  config.before(:each) do
    Delayed::Worker.delay_jobs = true
    GC.disable
    if example.options[:db_cleaner_strategy].in? [:transaction, :truncation, :deletion]
      DatabaseCleaner.strategy = example.options[:db_cleaner_strategy]
    elsif Capybara.current_driver == :rack_test
      DatabaseCleaner.strategy = :transaction
    else
      # Need to allow a bit longer for CI server to have enough time to finish the css request
      page.driver.server.timeout = 120 if page.driver.is_a? Capybara::Poltergeist::Driver

      DatabaseCleaner.strategy = :truncation
    end

    DatabaseCleaner.start
  end

  config.before(:all) do
    savon.mock!
  end

  config.after(:each) do
    DatabaseCleaner.clean
    Timecop.return
    GC.enable
  end

  config.after(:all) do
    FileUtils.touch "#{Rails.root}/tmp/cache/.gitkeep"
    savon.unmock!
  end
end

# Convenience method to temporarily disable clearing the flash at the end of the action.
def disable_flash_now_sweeper
  @controller.instance_eval { flash.stubs(:sweep) }
end

# allows capybara tests to use post instead of get requests
def visit_via_post(path)
  page.driver.post(path)
end

def with_user_agent(user_agent, &block)
  user_agent_by_keyword = {
    :iphone => "Mozilla/5.0 (iPhone; CPU iPhone OS 5_0_1 like Mac OS X) AppleWebKit/534.46 (KHTML, like Gecko) Version/5.1 Mobile/9A405 Safari/7534.48.3",
    :android => "Mozilla/5.0 (Linux; U; Android 2.3.3; en-gb; GT-I9100 Build/GINGERBREAD) AppleWebKit/533.1 (KHTML, like Gecko) Version/4.0 Mobile Safari/533.1"
  }
  if user_agent_by_keyword[user_agent.to_sym]
    user_agent = user_agent_by_keyword[user_agent.to_sym]
  end

  if page.driver.instance_of? Capybara::RackTest::Driver
    original_options = page.driver.instance_variable_get("@options")
    options = original_options.merge(:headers => { "HTTP_USER_AGENT" => user_agent.to_s })
    page.driver.instance_variable_set("@options", options)

    begin
      yield
    ensure
      page.driver.instance_variable_set("@options", original_options)
    end

  else
    ActionDispatch::Request.any_instance.stubs(:user_agent).returns user_agent
    yield
  end

end

def pause
  sleep 1
end

def active_merchant_credit_card(number = '4242424242424242', options = {})
  defaults = {
    :number => number,
    :month => 9,
    :year => Time.now.year + 1,
    :first_name => 'Longbob',
    :last_name => 'Longsen',
    :verification_value => '123',
    :brand => 'visa'
  }.update(options)

  ActiveMerchant::Billing::CreditCard.new(defaults)
end

def zendesk_api_url(collection)
  "https://#{Rack::Utils.escape(ZENDESK_API_USERNAME+'/')}token:#{ZENDESK_API_TOKEN}@#{ZENDESK_API_URL[8..-1]}/#{collection.to_s}"
end

# Admin property membership list
def membership_username_list
  username_list = []
  all("table tbody tr").each do |row|
    username_list << row.all("td a").first.text
  end
  username_list
end
