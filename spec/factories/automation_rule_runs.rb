FactoryBot.define do
  factory :automation_rule_run do
    automation_rule
    account { automation_rule.account }
    outcome { 'executed' }
    created_at { Time.current }
  end
end
