FactoryBot.define do
  factory :calendar_connection do
    account
    provider { 'google' }
    sequence(:email) { |n| "agenda#{n}@example.com" }
    refresh_token { 'refresh' }
  end
end
