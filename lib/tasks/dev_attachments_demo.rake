namespace :dev do
  desc 'Seed isolated attachment scenarios (ACCOUNT_ID=1, RESET=1 to recreate; never production)'
  task attachments_demo: :environment do
    abort 'dev:attachments_demo is disabled in production' if Rails.env.production?

    require_relative '../seeders/attachments_demo'
    Seeders::AttachmentsDemo.new(account: Account.find(ENV.fetch('ACCOUNT_ID', '1'))).perform!(reset: ENV['RESET'] == '1')
  end
end
