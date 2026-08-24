# == Schema Information
#
# Table name: calendar_events
#
#  id                     :bigint           not null, primary key
#  appointment_status     :string           default("none"), not null
#  bot_followup_policy    :jsonb            not null
#  end_at                 :datetime
#  etag                   :string
#  external_calendar_id   :string           not null
#  google_event_id        :string           not null
#  html_link              :string
#  start_at               :datetime
#  summary                :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  calendar_connection_id :bigint           not null
#  contact_id             :bigint
#  conversation_id        :bigint
#  created_by_id          :bigint
#  updated_by_id          :bigint
#  idempotency_key        :string
#
class CalendarEvent < ApplicationRecord
  APPOINTMENT_STATUSES = %w[none pending_confirmation confirmed cancelled rescheduled].freeze

  belongs_to :account
  belongs_to :calendar_connection
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :updated_by, class_name: 'User', optional: true
  belongs_to :deleted_by, class_name: 'User', optional: true
  belongs_to :contact, optional: true
  belongs_to :conversation, optional: true
  has_many :activities, class_name: 'CalendarEventActivity', dependent: :destroy

  store_accessor :bot_followup_policy, :enabled, :confirmation, :reminders_minutes_before, :source

  validates :external_calendar_id, presence: true
  validates :google_event_id, presence: true
  validates :google_event_id, uniqueness: { scope: :calendar_connection_id }
  validates :idempotency_key, uniqueness: { scope: :account_id }, allow_nil: true
  validates :appointment_status, inclusion: { in: APPOINTMENT_STATUSES }

  scope :kept, -> { where(deleted_at: nil) }

  def discarded?
    deleted_at.present?
  end

  def bot_followup_enabled?
    ActiveModel::Type::Boolean.new.cast(bot_followup_policy.is_a?(Hash) ? bot_followup_policy['enabled'] : enabled)
  end
end
