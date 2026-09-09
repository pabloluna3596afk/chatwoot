# == Schema Information
#
# Table name: automation_rules
#
#  id              :bigint           not null, primary key
#  actions         :jsonb            not null
#  active          :boolean          default(TRUE), not null
#  conditions      :jsonb            not null
#  description     :text
#  event_name      :string           not null
#  execution_delay :integer
#  name            :string           not null
#  schedule        :jsonb            not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#
# Indexes
#
#  index_automation_rules_on_account_id  (account_id)
#
class AutomationRule < ApplicationRecord
  include Rails.application.routes.url_helpers
  include Reauthorizable

  EXECUTION_DELAY_RANGE = (10..43_200) # minutes: 10 min to 30 days
  # Conversation-level delayed rules key their episode on status; only status and attributes
  # that never change after the delay (inbox) are safe to also filter on.
  DELAYED_CONVERSATION_ATTRIBUTES = %w[status inbox_id].freeze
  # Schedule kinds that scan contacts instead of conversations (see
  # Automations::ContactBasedRuleRunner) — a birthday, a last purchase or a last
  # activity lives on the contact, and TimeBasedRuleRunner can never reach a
  # contact with no open conversation.
  CONTACT_BASED_SCHEDULE_KINDS = %w[contact_date].freeze
  CONTACT_DATE_SOURCES = %w[contact_attribute last_activity].freeze
  CONTACT_DATE_RECURRENCES = %w[once yearly].freeze

  belongs_to :account
  has_many :pending_executions, class_name: 'AutomationRulePendingExecution', dependent: :delete_all
  has_many_attached :files

  validate :json_conditions_format
  validate :json_actions_format
  validate :query_operator_presence
  validate :query_operator_value
  validate :schedule_format, if: :time_triggered?
  validates :account_id, presence: true
  validates :execution_delay, numericality: { only_integer: true, in: EXECUTION_DELAY_RANGE }, allow_nil: true
  validate :execution_delay_supported_conditions
  validate :execution_delay_supported_event

  after_update_commit :reauthorized!, if: -> { saved_change_to_conditions? }
  # Discard rows armed under the old definition; they re-arm on the next matching event.
  after_update :discard_stale_pending_executions, if: :execution_config_changed?

  scope :active, -> { where(active: true) }

  def time_triggered?
    event_name == 'time_triggered'
  end

  def contact_based_schedule?
    CONTACT_BASED_SCHEDULE_KINDS.include?(schedule_value(:kind).to_s)
  end

  def conditions_attributes
    %w[content email country_code status message_type browser_language assignee_id team_id referer city company_name inbox_id
       mail_subject phone_number priority conversation_language labels private_note days_since hours_since_last_outgoing
       hours_since_last_incoming]
  end

  def actions_attributes
    %w[send_message send_whatsapp_template add_label remove_label send_email_to_team assign_team assign_agent
       remove_assigned_agent remove_assigned_team send_webhook_event mute_conversation send_attachment change_status
       resolve_conversation open_conversation pending_conversation snooze_conversation change_priority
       send_email_transcript add_private_note update_contact_custom_attribute update_conversation_custom_attribute
       execute_macro enter_flow notify_assignee].freeze
  end

  def file_base_data
    files.map do |file|
      {
        id: file.id,
        automation_rule_id: id,
        file_type: file.content_type,
        account_id: account_id,
        file_url: url_for(file),
        blob_id: file.blob_id,
        filename: file.filename.to_s
      }
    end
  end

  private

  def schedule_format
    kind = schedule_value(:kind).to_s
    errors.add(:schedule, 'kind is required for time_triggered rules') if kind.blank?
    return days_since_attribute_schedule_format if kind == 'days_since_attribute'
    return contact_date_schedule_format if kind == 'contact_date'
  end

  def days_since_attribute_schedule_format
    relative_to = schedule_value(:relative_to).to_s.presence || 'after'
    unless %w[after on before].include?(relative_to)
      errors.add(:schedule, 'relative_to must be after, on, or before')
      return
    end

    if schedule_value(:attribute_key).to_s.blank?
      errors.add(:schedule, 'attribute_key is required')
      return
    end

    return if relative_to == 'on'

    days = schedule_hash[:days] || schedule_hash['days']
    errors.add(:schedule, 'days must be 1 or greater') if days.to_i < 1
  end

  # Contact-based rules need an inbox to create a conversation in when the matching
  # contact has none yet (see Automations::ContactBasedRuleRunner#resolve_conversation).
  def contact_date_schedule_format
    return unless contact_date_source_valid?
    return unless contact_date_recurrence_valid?
    return unless contact_date_relative_to_valid?
    return unless contact_date_inbox_valid?

    return if (schedule_value(:relative_to).to_s.presence || 'on') == 'on'

    days = schedule_hash[:days] || schedule_hash['days']
    errors.add(:schedule, 'days must be 1 or greater') if days.to_i < 1
  end

  def contact_date_source_valid?
    source = schedule_value(:date_source).to_s.presence || 'contact_attribute'
    unless CONTACT_DATE_SOURCES.include?(source)
      errors.add(:schedule, "date_source must be one of #{CONTACT_DATE_SOURCES.join(', ')}")
      return false
    end

    # last_activity reads a column; only an attribute source needs a key.
    if source == 'contact_attribute' && schedule_value(:attribute_key).to_s.blank?
      errors.add(:schedule, 'attribute_key is required')
      return false
    end

    true
  end

  # Only a calendar date can come around again; last_activity moves forward on
  # its own, so a yearly window there would never mean anything.
  def contact_date_recurrence_valid?
    recurrence = schedule_value(:recurrence).to_s.presence || 'once'
    unless CONTACT_DATE_RECURRENCES.include?(recurrence)
      errors.add(:schedule, "recurrence must be one of #{CONTACT_DATE_RECURRENCES.join(', ')}")
      return false
    end

    source = schedule_value(:date_source).to_s.presence || 'contact_attribute'
    if recurrence == 'yearly' && source != 'contact_attribute'
      errors.add(:schedule, 'recurrence yearly requires a contact_attribute date_source')
      return false
    end

    true
  end

  def contact_date_relative_to_valid?
    relative_to = schedule_value(:relative_to).to_s.presence || 'on'
    return true if %w[after on before].include?(relative_to)

    errors.add(:schedule, 'relative_to must be after, on, or before')
    false
  end

  def contact_date_inbox_valid?
    target_inbox_id = schedule_value(:target_inbox_id)
    if target_inbox_id.blank?
      errors.add(:schedule, 'target_inbox_id is required')
      return false
    end

    return true if account.inboxes.exists?(id: target_inbox_id)

    errors.add(:schedule, 'target_inbox_id must belong to the account')
    false
  end

  def schedule_hash
    schedule.is_a?(Hash) ? schedule : {}
  end

  def schedule_value(key)
    schedule_hash[key.to_s].presence || schedule_hash[key]
  end

  def json_conditions_format
    return if conditions.blank?

    attributes = conditions.map { |obj, _| obj['attribute_key'] }
    conditions = attributes - conditions_attributes
    conditions -= account.custom_attribute_definitions.pluck(:attribute_key)
    errors.add(:conditions, "Automation conditions #{conditions.join(',')} not supported.") if conditions.any?
  end

  def json_actions_format
    return if actions.blank?

    attributes = actions.map { |obj, _| obj['action_name'] }
    actions = attributes - actions_attributes

    errors.add(:actions, "Automation actions #{actions.join(',')} not supported.") if actions.any?
  end

  def query_operator_presence
    return if conditions.blank?

    operators = conditions.select { |obj, _| obj['query_operator'].nil? }
    errors.add(:conditions, 'Automation conditions should have query operator.') if operators.length > 1
  end

  def query_operator_value
    return if conditions.blank?

    conditions.each do |obj|
      validate_single_condition(obj)
    end
  end

  # The fire-time re-check cannot reconstruct changed_attributes, so delayed rules
  # cannot use attribute_changed conditions.
  def execution_delay_supported_conditions
    return if execution_delay.blank? || conditions.blank?
    return if conditions.none? { |obj| obj['filter_operator'] == 'attribute_changed' }

    errors.add(:execution_delay, 'cannot be used with attribute_changed conditions.')
  end

  # Conversation-level episodes key on status_changed_at alone. Mutable attributes would collapse
  # distinct periods into one episode, so only status and immutable filters (inbox) are allowed.
  def execution_delay_supported_event
    return if execution_delay.blank? || conditions.blank? || event_name == 'message_created'
    return if conditions.all? { |obj| DELAYED_CONVERSATION_ATTRIBUTES.include?(obj['attribute_key']) }

    errors.add(:execution_delay, 'only supports status and inbox conditions for conversation-level events.')
  end

  # Deactivating counts: without it a rule turned off and back on before its due time would still
  # run the actions the admin turned it off to stop.
  def execution_config_changed?
    saved_change_to_active? || saved_change_to_execution_delay? || saved_change_to_event_name? ||
      saved_change_to_conditions? || saved_change_to_actions?
  end

  def discard_stale_pending_executions
    # armed = pending + processing, the rows the sweep would otherwise still run. Rows already
    # executing are left alone: their actions are in flight and cannot be called back.
    pending_executions.armed.delete_all
  end

  def validate_single_condition(condition)
    query_operator = condition['query_operator']

    return if query_operator.nil?
    return if query_operator.empty?

    operator = query_operator.upcase
    errors.add(:conditions, 'Query operator must be either "AND" or "OR"') unless %w[AND OR].include?(operator)
  end
end

AutomationRule.include_mod_with('Audit::AutomationRule')
AutomationRule.prepend_mod_with('AutomationRule')
