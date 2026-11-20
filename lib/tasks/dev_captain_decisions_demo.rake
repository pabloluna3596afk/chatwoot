namespace :dev do
  desc 'Seed fictional Captain decision scenarios (ACCOUNT_ID=1; never production)'
  task captain_decisions_demo: :environment do
    abort 'dev:captain_decisions_demo is disabled in production' if Rails.env.production?

    require_relative '../seeders/captain_decisions_demo'
    Seeders::CaptainDecisionsDemo.new(account: Account.find(ENV.fetch('ACCOUNT_ID', '1'))).perform!
  end
end
