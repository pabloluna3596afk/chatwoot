class AutomationRuleRun < ApplicationRecord
  OUTCOMES = %w[executed skipped failed].freeze
  RETENTION_WINDOW = 30.days

  belongs_to :account
  belongs_to :automation_rule
  belongs_to :conversation, optional: true
  belongs_to :contact, optional: true

  validates :outcome, inclusion: { in: OUTCOMES }
end
