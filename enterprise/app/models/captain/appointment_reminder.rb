# == Schema Information
#
# Table name: captain_appointment_reminders
#
#  id                   :bigint           not null, primary key
#  kind                 :string           not null
#  scheduled_at         :datetime         not null
#  sent_at              :datetime
#  skipped_reason       :string
#  status               :string           default("pending"), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  calendar_event_id    :bigint           not null
#  captain_assistant_id :bigint           not null
#  conversation_id      :bigint           not null
#
# Indexes
#
#  index_captain_appointment_reminders_on_account_id  (account_id)
#  index_captain_reminders_on_event_and_kind          (calendar_event_id,kind) UNIQUE
#  index_captain_reminders_on_status_and_scheduled_at (status,scheduled_at)
#
# One row per reminder of an appointment booked by Captain: 24 h and 2 h before it starts. The unique
# (event, kind) index is what keeps a reminder from ever being created, and so sent, twice.
class Captain::AppointmentReminder < ApplicationRecord
  self.table_name = 'captain_appointment_reminders'

  LEAD_TIMES = { 'reminder_24h' => 24.hours, 'reminder_2h' => 2.hours }.freeze
  KINDS = LEAD_TIMES.keys.freeze
  STATUSES = %w[pending sent skipped cancelled].freeze

  belongs_to :account
  belongs_to :calendar_event
  belongs_to :captain_assistant, class_name: 'Captain::Assistant'
  belongs_to :conversation

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :kind, uniqueness: { scope: :calendar_event_id }

  scope :pending, -> { where(status: 'pending') }
  scope :due, ->(now = Time.current) { pending.where(scheduled_at: ..now) }

  def lead_time
    LEAD_TIMES.fetch(kind)
  end
end
