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
#  invitation_status      :string
#
class CalendarEvent < ApplicationRecord
  APPOINTMENT_STATUSES = %w[none pending_confirmation confirmed cancelled rescheduled].freeze
  BOOKING_SOURCES = %w[manual ai].freeze
  CUSTOMER_REMINDER_LEAD_TIME = 24.hours
  CUSTOMER_REMINDER_PENDING_STATUSES = [nil, 'no_template', 'retry_1', 'retry_2'].freeze
  INVITATION_STATUSES = %w[needs_action accepted declined tentative].freeze

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
  validates :booking_source, inclusion: { in: BOOKING_SOURCES }
  validates :invitation_status, inclusion: { in: INVITATION_STATUSES }, allow_nil: true

  scope :kept, -> { where(deleted_at: nil).where.not(appointment_status: 'cancelled') }

  scope :customer_reminder_pending, lambda {
    kept.where(customer_reminder_sent_at: nil, customer_reminder_status: CUSTOMER_REMINDER_PENDING_STATUSES)
        .where.not(booking_source: 'ai').where.not(conversation_id: nil)
  }

  before_save :reset_customer_reminder, if: :will_save_change_to_start_at?
  before_update :release_booking_key_on_move
  after_commit :broadcast_appointment_change, on: [:create, :update, :destroy]
  after_commit :enqueue_appointment_attributes_update, on: [:create, :update, :destroy]

  def discarded?
    deleted_at.present? || appointment_status == 'cancelled'
  end

  def bot_followup_enabled?
    ActiveModel::Type::Boolean.new.cast(bot_followup_policy.is_a?(Hash) ? bot_followup_policy['enabled'] : enabled)
  end

  def ai_booked?
    booking_source == 'ai'
  end

  private

  def reset_customer_reminder
    self.customer_reminder_sent_at = nil
    self.customer_reminder_status = nil
    return unless account.customer_reminders_enabled == true && !ai_booked? && !bot_followup_enabled?

    self.customer_reminder_status = 'skipped_too_close' if start_at && start_at < Time.current + CUSTOMER_REMINDER_LEAD_TIME
  end

  # A key belongs to the booked interval. Moving (locally or through Google sync) releases it;
  # the moved event keeps its identity, while a new booking of the old interval gets a new event.
  def release_booking_key_on_move
    self.idempotency_key = nil if will_save_change_to_start_at? || will_save_change_to_end_at?
  end

  def broadcast_appointment_change
    # Google reads may change only etag/updated_at; never turn a read into a reload loop.
    fields = %w[contact_id conversation_id start_at end_at summary appointment_status invitation_status deleted_at created_by_id booking_source]
    return unless destroyed? || previous_changes.keys.intersect?(fields)

    contact_ids = [contact_id, previous_changes.dig('contact_id', 0)].compact.uniq
    return if contact_ids.empty?

    ActionCableBroadcastJob.perform_later(
      ["account_#{account_id}"], 'calendar.events_changed', { account_id: account_id, contact_ids: contact_ids }
    )
  end

  def enqueue_appointment_attributes_update
    fields = %w[contact_id start_at summary appointment_status deleted_at]
    return unless destroyed? || previous_changes.keys.intersect?(fields)

    contact_ids = [contact_id, previous_changes.dig('contact_id', 0)].compact.uniq
    contact_ids.each { |id| Calendar::AppointmentAttributes::UpdateJob.perform_later(account_id, id) }
    enqueue_appointment_start_refresh
  end

  # "Next appointment" becomes "last appointment" when it starts: refresh the contact right after that moment.
  def enqueue_appointment_start_refresh
    return if destroyed? || contact_id.blank? || discarded? || start_at.blank? || start_at <= Time.current

    Calendar::AppointmentAttributes::UpdateJob.set(wait_until: start_at + 1.minute).perform_later(account_id, contact_id)
  end
end

CalendarEvent.prepend_mod_with('CalendarEvent')
