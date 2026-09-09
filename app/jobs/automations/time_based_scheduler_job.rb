# frozen_string_literal: true

class Automations::TimeBasedSchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    AutomationRule.active.where(event_name: 'time_triggered').find_each do |rule|
      runner_for(rule).perform
    end
  end

  private

  def runner_for(rule)
    return Automations::ContactBasedRuleRunner.new(rule) if rule.contact_based_schedule?

    Automations::TimeBasedRuleRunner.new(rule)
  end
end
