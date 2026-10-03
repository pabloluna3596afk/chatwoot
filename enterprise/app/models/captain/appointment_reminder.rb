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

  KINDS = Captain::AppointmentsSettings::REMINDER_KEYS
  # Rows scheduled before the reminders were editable keep their old kind.
  ALL_KINDS = (KINDS + Captain::AppointmentsSettings::LEGACY_KINDS.keys).freeze
  STATUSES = %w[pending sent skipped cancelled].freeze

  belongs_to :account
  belongs_to :calendar_event
  belongs_to :captain_assistant, class_name: 'Captain::Assistant'
  belongs_to :conversation, class_name: '::Conversation'

  validates :kind, inclusion: { in: ALL_KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :kind, uniqueness: { scope: :calendar_event_id }

  scope :pending, -> { where(status: 'pending') }
  scope :due, ->(now = Time.current) { pending.where(scheduled_at: ..now) }

  def pending?
    status == 'pending'
  end

  # How long before the appointment this reminder goes out, from what the assistant has configured now.
  def lead_time
    captain_assistant.appointments.hours_before(kind).hours
  end
end
