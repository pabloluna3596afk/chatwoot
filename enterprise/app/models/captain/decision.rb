class Captain::Decision < ApplicationRecord
  self.table_name = 'captain_decisions'

  KINDS = %w[
    loop_guard reply resolve handoff completion_signal completion_review close_unanswered nudge reengage reopen
    human_control disengage
  ].freeze
  OUTCOMES = %w[created completed pending confirmed rejected cancelled skipped failed].freeze
  ORIGINS = %w[model rule tool time].freeze
  TRIGGERS = %w[customer_message tool inactivity completion_signal evaluation error reply_limit usage_limit human_action assignment engagement].freeze
  REASON_TEXT_LIMIT = 500
  PAYLOAD_LIMIT = 8.kilobytes

  belongs_to :account
  belongs_to :conversation, class_name: '::Conversation'
  belongs_to :assistant, class_name: 'Captain::Assistant', optional: true
  belongs_to :anchor_message, class_name: '::Message', optional: true
  belongs_to :agent_session, class_name: 'Captain::AgentSession', optional: true
  belongs_to :parent_decision, class_name: 'Captain::Decision', optional: true
  has_many :child_decisions, class_name: 'Captain::Decision', foreign_key: :parent_decision_id, dependent: :nullify, inverse_of: :parent_decision

  validates :version, inclusion: { in: [1] }
  validates :kind, inclusion: { in: KINDS }
  validates :outcome, inclusion: { in: OUTCOMES }
  validates :origin, inclusion: { in: ORIGINS }
  validates :trigger, inclusion: { in: TRIGGERS }
  validates :decision_key, presence: true, length: { maximum: 200 }, uniqueness: { scope: :account_id }
  validates :reason_code, presence: true, length: { maximum: 80 }
  validates :reason_locale, presence: true, length: { maximum: 16 }
  validates :reason_text, length: { maximum: REASON_TEXT_LIMIT }
  validates :occurred_at, presence: true
  validates_with Captain::Decisions::PayloadValidator
  validates_with Captain::Decisions::ReferencesValidator
end
