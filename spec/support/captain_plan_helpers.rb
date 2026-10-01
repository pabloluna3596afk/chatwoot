# Captain quotas come from the account's plan and its usage period (AccountPlanUsage). An account with no plan is
# neither metered nor limited, so specs that count or exhaust Captain responses put the account on a plan first.
module CaptainPlanHelpers
  # `used` and `copilot_used` are what the current period already consumed. The columns are set directly so the
  # account's plan callbacks (which also switch Captain features on) do not change what the spec sets up.
  def put_account_on_plan(account, monthly_messages: 100, used: 0, copilot_used: 0, **plan_attributes)
    plan = Plan.create!(
      { name: 'Spec plan', slug: "spec-plan-#{SecureRandom.hex(4)}", monthly_messages: monthly_messages, max_documents: 100, max_captain_assistants: 100, max_inboxes: 100, max_human_agents: 100 }
        .merge(plan_attributes)
    )
    account.update_columns(plan_id: plan.id, plan_started_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    account.reload.current_usage_period.update!(responses_consumed: used, copilot_responses_consumed: copilot_used)
    plan
  end

  def captain_responses_used(account)
    account.reload.current_usage_period&.responses_consumed.to_i
  end

  def copilot_responses_used(account)
    account.reload.current_usage_period&.copilot_responses_consumed.to_i
  end
end

RSpec.configure { |config| config.include CaptainPlanHelpers }
