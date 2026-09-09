# frozen_string_literal: true

# Contact-level sibling of TimeBasedRuleRunner. A conversation-scoped scan can
# never reach a contact whose only qualifying date lives on the contact itself
# — a birthday, a last purchase, a last activity — when that contact has no
# open conversation. This runner starts from contacts instead.
#
# The trigger is deliberately split into three independent knobs so one engine
# covers every proactive case instead of one case each:
#
#   date_source  where the date comes from (a contact attribute, last activity)
#   recurrence   'yearly' repeats every year (birthday, anniversary);
#                'once' fires a single time per value (repurchase, win-back)
#   relative_to  before / on / after, with days
#
#   birthday      contact_attribute + yearly + on
#   anniversary   contact_attribute + yearly + on
#   repurchase    contact_attribute + once   + after 30
#   appointment   contact_attribute + once   + before 1
#   win-back      last_activity     + once   + after 60
#
# For every matching contact it finds or creates a conversation in the rule's
# target inbox and hands off to AutomationRules::ActionService exactly like the
# conversation-based runner — the action pipeline itself is untouched.
class Automations::ContactBasedRuleRunner
  LEDGER_TTL = 400.days.to_i # a year plus slack, so yearly rules outlive leap years
  RELATIVE_TO_VALUES = %w[after on before].freeze
  DATE_SOURCES = %w[contact_attribute last_activity].freeze
  RECURRENCES = %w[once yearly].freeze

  def initialize(rule)
    @rule = rule
    @account = rule.account
    @schedule = (@rule.schedule || {}).with_indifferent_access
  end

  def perform
    return unless @schedule[:kind].to_s == 'contact_date'
    return if target_inbox.blank?
    return if date_source == 'contact_attribute' && attribute_key.blank?

    candidates.find_each(batch_size: 50) do |contact|
      next unless test_mode_allows?(contact)

      unless cap.within_cap?
        pause_for_cap!
        break
      end

      next unless claim_window!(contact)

      conversation = resolve_conversation(contact)
      next if conversation.blank?
      next unless conditions_match?(conversation)

      AutomationRules::ActionService.new(@rule, @account, conversation).perform
      cap.increment!
    end
  end

  private

  def cap
    @cap ||= Automations::ProactiveSendCap.new(@account)
  end

  def target_inbox
    @target_inbox ||= @account.inboxes.find_by(id: @schedule[:target_inbox_id])
  end

  def attribute_key
    @schedule[:attribute_key].to_s
  end

  def date_source
    value = @schedule[:date_source].to_s.presence || 'contact_attribute'
    DATE_SOURCES.include?(value) ? value : 'contact_attribute'
  end

  # Only a date that recurs on the calendar can repeat yearly. "Last activity"
  # moves forward on its own, so a yearly window there would be meaningless.
  def recurrence
    value = @schedule[:recurrence].to_s.presence || 'once'
    return 'once' unless RECURRENCES.include?(value)
    return 'once' unless date_source == 'contact_attribute'

    value
  end

  def relative_to
    value = @schedule[:relative_to].to_s.presence || 'on'
    RELATIVE_TO_VALUES.include?(value) ? value : 'on'
  end

  # The date the source must land on for today to be the right day to fire.
  def target_date
    days = relative_to == 'on' ? 0 : @schedule[:days].to_i
    case relative_to
    when 'before' then Time.zone.today + days
    when 'after' then Time.zone.today - days
    else Time.zone.today
    end
  end

  def candidates
    scope = @account.contacts
    target = target_date

    if recurrence == 'yearly'
      # Month/day match, ignoring the year — so it comes around again every
      # year. A Feb 29 value only matches in leap years, like the real date.
      scope.where("#{date_sql} IS NOT NULL")
           .where("EXTRACT(MONTH FROM (#{date_sql})) = ?", target.month)
           .where("EXTRACT(DAY FROM (#{date_sql})) = ?", target.day)
    else
      # Same comparison the conversation-based runner uses: "after" catches up
      # on anything already past due, the others match the exact day.
      operator = relative_to == 'after' ? '<=' : '='
      scope.where("#{date_sql} IS NOT NULL")
           .where("#{date_sql} #{operator} ?", target)
    end
  end

  # Built with a quoted literal rather than a bind so the same fragment can be
  # reused across several where clauses without the placeholder counts drifting.
  def date_sql
    @date_sql ||=
      if date_source == 'last_activity'
        'contacts.last_activity_at::date'
      else
        quoted = ActiveRecord::Base.connection.quote(attribute_key)
        <<~SQL.squish
          CASE
            WHEN (contacts.custom_attributes ->> #{quoted}) ~ '^\\d{4}-\\d{2}-\\d{2}'
            THEN LEFT(contacts.custom_attributes ->> #{quoted}, 10)::date
            ELSE NULL
          END
        SQL
      end
  end

  def test_mode_allows?(contact)
    label = @schedule[:test_mode_label].to_s
    return true if label.blank?

    contact.label_list.include?(label)
  end

  def conditions_match?(conversation)
    return true if @rule.conditions.blank?

    AutomationRules::ConditionsFilterService.new(@rule, conversation).perform
  end

  def resolve_conversation(contact)
    existing = target_inbox.conversations.where(contact_id: contact.id).order(created_at: :desc).first
    return existing if existing.present?

    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: target_inbox, hmac_verified: true).perform
    return if contact_inbox.blank?

    Conversation.create!(
      account_id: @account.id,
      inbox_id: target_inbox.id,
      contact_id: contact.id,
      contact_inbox_id: contact_inbox.id
    )
  rescue StandardError => e
    Rails.logger.error(
      "[ContactBasedRuleRunner] failed to resolve conversation rule=#{@rule.id} contact=#{contact.id}: #{e.message}"
    )
    nil
  end

  def claim_window!(contact)
    key = format(
      ::Redis::Alfred::AUTOMATION_CONTACT_RULE_LEDGER,
      rule_id: @rule.id,
      contact_id: contact.id,
      window: window_id(contact)
    )
    ::Redis::Alfred.set(key, Time.now.utc.to_i, nx: true, ex: LEDGER_TTL)
  end

  # yearly keys on the scan year, so the same contact comes around again next
  # year. once keys on the date itself, so it fires a single time per value —
  # and fires again later if that value moves (a new purchase, new activity).
  def window_id(contact)
    base = "#{date_source}:#{attribute_key}:#{@schedule[:days]}:#{relative_to}"
    return "#{base}:yearly:#{Time.zone.today.year}" if recurrence == 'yearly'

    "#{base}:once:#{source_date_for(contact)}"
  end

  def source_date_for(contact)
    return contact.last_activity_at&.to_date if date_source == 'last_activity'

    (contact.custom_attributes || {})[attribute_key]
  end

  # Pausing (rather than silently resuming once the day's count resets) forces
  # an admin to look at volume before this rule sends again.
  def pause_for_cap!
    return unless @rule.active?

    @rule.update!(active: false)
    Rails.logger.error(
      "[ContactBasedRuleRunner] paused rule=#{@rule.id} account=#{@account.id}: " \
      'daily proactive send cap reached — review volume before reactivating'
    )
  end
end
