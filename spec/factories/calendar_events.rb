FactoryBot.define do
  factory :calendar_event do
    account { calendar_connection.account }
    calendar_connection
    external_calendar_id { 'primary' }
    sequence(:google_event_id) { |n| "event-#{n}" }
    summary { 'Appointment' }
    start_at { 1.day.from_now }
    end_at { start_at + 30.minutes }
  end
end
