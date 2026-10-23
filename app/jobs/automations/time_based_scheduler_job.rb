# frozen_string_literal: true

class Automations::TimeBasedSchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    # find_each discards the shared execution order.
    AutomationRule.active.in_execution_order.where(event_name: 'time_triggered').each do |rule| # rubocop:disable Rails/FindEach
      runner_for(rule).perform
    end
  end

  private

  def runner_for(rule)
    return Automations::ContactBasedRuleRunner.new(rule) if rule.contact_based_schedule?

    Automations::TimeBasedRuleRunner.new(rule)
  end
end
