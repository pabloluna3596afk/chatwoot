FactoryBot.define do
  factory :captain_decision, class: 'Captain::Decision' do
    account
    conversation { association :conversation, account: account }
    assistant { association :captain_assistant, account: account }
    sequence(:decision_key) { |n| "reply:#{n}" }
    kind { 'reply' }
    outcome { 'created' }
    origin { 'model' }
    trigger { 'customer_message' }
    reason_code { 'model_reply' }
    reason_locale { 'en' }
    occurred_at { Time.current }
  end
end
