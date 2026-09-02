# frozen_string_literal: true

# Answers "if this event happened on this conversation right now, which rules
# would fire and what would they do?" — without doing any of it.
#
# Deliberately reuses ConditionsFilterService, the same evaluator the listener
# uses in production (AutomationRuleListener#message_created / #process_conversation_event).
# Reimplementing the matching logic here would drift from real behaviour the
# first time either side changed, and a simulator you can't trust is worse than
# none.
#
# Nothing is executed: ActionService is never called, only described.
class AutomationRules::SimulationService
  Result = Struct.new(:event_name, :conversation_id, :matches, :evaluated_count, keyword_init: true)
  Match = Struct.new(:rule_id, :rule_name, :actions, :order, keyword_init: true)

  # Events a conversation can be simulated against. time_triggered is excluded
  # on purpose: the listener skips it too (current_account_rules returns none),
  # it runs from Automations::TimeBasedRuleRunner on its own schedule.
  SIMULATABLE_EVENTS = %w[
    conversation_created conversation_updated conversation_opened
    conversation_resolved message_created
  ].freeze

  def initialize(account:, conversation:, event_name:)
    @account = account
    @conversation = conversation
    @event_name = event_name.to_s
  end

  def perform
    rules = candidate_rules
    matches = []

    rules.each_with_index do |rule, index|
      next unless conditions_match?(rule)

      matches << Match.new(
        rule_id: rule.id,
        rule_name: rule.name,
        actions: describe_actions(rule),
        # Runtime has no ORDER BY, so this mirrors the DB's default order —
        # which is what decides who wins when two rules collide.
        order: index + 1
      )
    end

    Result.new(
      event_name: @event_name,
      conversation_id: @conversation.id,
      matches: matches,
      evaluated_count: rules.size
    )
  end

  private

  def candidate_rules
    return AutomationRule.none unless SIMULATABLE_EVENTS.include?(@event_name)

    # Same selection the listener performs.
    AutomationRule.where(
      event_name: @event_name,
      account_id: @account.id,
      active: true
    )
  end

  def conditions_match?(rule)
    options = {}
    # message_created rules are evaluated against a specific message in
    # production; use the conversation's latest one so message-scoped
    # conditions (content, message_type, private_note) behave realistically.
    options[:message] = @conversation.messages.last if @event_name == 'message_created'

    ::AutomationRules::ConditionsFilterService.new(rule, @conversation, options).perform.present?
  rescue StandardError => e
    Rails.logger.error "Simulation failed for automation rule #{rule.id}: #{e.message}"
    false
  end

  def describe_actions(rule)
    Array(rule.actions).filter_map do |action|
      next unless action.is_a?(Hash)

      name = action['action_name'].to_s
      next if name.blank?

      { action_name: name, action_params: Array(action['action_params']) }
    end
  end
end
