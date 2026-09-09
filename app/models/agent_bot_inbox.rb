# == Schema Information
#
# Table name: agent_bot_inboxes
#
#  id           :bigint           not null, primary key
#  status       :integer          default("active")
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :integer
#  agent_bot_id :integer
#  inbox_id     :integer
#

class AgentBotInbox < ApplicationRecord
  # own_hours: bot only replies inside its own weekly schedule (bot_working_hours).
  # outside_inbox_hours: bot covers exactly when the inbox's own working hours say
  #   humans are out of office — complements human coverage instead of overlapping it.
  # always: bot replies whenever the inbox itself is open (unchanged default behavior).
  SCHEDULE_MODES = %w[own_hours outside_inbox_hours always].freeze

  validates :inbox_id, presence: true
  validates :agent_bot_id, presence: true
  validates :schedule_mode, inclusion: { in: SCHEDULE_MODES }
  before_validation :ensure_account_id

  belongs_to :inbox
  belongs_to :agent_bot
  belongs_to :account
  has_many :bot_working_hours, class_name: 'AgentBotInboxWorkingHour', dependent: :destroy_async
  enum status: { active: 0, inactive: 1 }

  def bot_active_at?(time = Time.current)
    case schedule_mode
    when 'own_hours'
      bot_working_hours.find_by(day_of_week: time.in_time_zone(inbox.timezone).wday)&.open_at?(time) || false
    when 'outside_inbox_hours'
      inbox.out_of_office?
    else
      true
    end
  end

  private

  def ensure_account_id
    self.account_id = inbox&.account_id
  end
end
