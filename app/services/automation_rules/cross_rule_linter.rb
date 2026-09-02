# frozen_string_literal: true

# Flags active rules that fight each other at runtime: two rules on the same
# trigger where one undoes what the other does, or where both set a single-valued
# attribute to different things.
#
# Split out of AutomationRules::LintService because it answers a different
# question. LintService asks "can this rule ever fire?" and blocks the save when
# the answer is no. This asks "will this rule collide with another?" and only
# warns — two rules on one trigger is sometimes exactly what you want.
#
# Order matters and is not knowable here: AutomationRuleListener#current_account_rules
# has no ORDER BY, so when two rules collide the effective winner is whichever the
# database happens to return last. That unpredictability is the reason to warn.
class AutomationRules::CrossRuleLinter
  Finding = AutomationRules::LintService::Finding

  # Actions that cannot sensibly coexist on the same trigger.
  CONTRADICTORY_ACTION_PAIRS = [
    %w[resolve_conversation open_conversation],
    %w[resolve_conversation pending_conversation],
    %w[open_conversation pending_conversation],
    %w[assign_agent remove_assigned_agent],
    %w[assign_team remove_assigned_team],
    %w[mute_conversation send_message]
  ].freeze

  # Actions where two rules setting *different* values collide (last one wins).
  SINGLE_VALUE_ACTIONS = %w[assign_agent assign_team change_status change_priority].freeze

  # @param rules [Array<AutomationRule>] the account's rules
  # @param subject [AutomationRule, nil] the rule being saved. When given, only
  #   pairs involving it are reported — you want feedback on yours, not on rules
  #   you did not touch.
  def initialize(rules:, subject: nil)
    @rules = Array(rules)
    @subject = subject
  end

  # @return [Array<Finding>]
  def perform
    active = candidate_rules.select { |rule| active_trigger?(rule) }
    return [] if active.size < 2

    active.group_by(&:event_name).flat_map { |_event_name, group| conflicts_within(group) }
  end

  private

  # The rule being saved stands in for the version still in the database, so an
  # edit is checked as it will be, not as it was.
  def candidate_rules
    return @rules unless @subject

    others = @rules.reject { |rule| same_rule?(rule, @subject) }
    others + [@subject]
  end

  def active_trigger?(rule)
    rule.active? && rule.event_name.present?
  end

  def conflicts_within(group)
    return [] if group.size < 2

    group.combination(2).flat_map do |left, right|
      reportable_pair?(left, right) ? action_conflicts(left, right) : []
    end
  end

  # Match by object identity, not by id: a rule that is still unsaved has no id,
  # so comparing ids both missed the new rule entirely and paired unrelated
  # unsaved rules with each other through `nil == nil`.
  def reportable_pair?(left, right)
    return true if @subject.nil?

    left.equal?(@subject) || right.equal?(@subject)
  end

  def same_rule?(rule, other)
    return true if rule.equal?(other)

    other.id.present? && rule.id == other.id
  end

  def action_conflicts(left, right)
    left_actions = action_map(left)
    right_actions = action_map(right)

    contradictory_action_warnings(left, right, left_actions, right_actions) +
      conflicting_value_warnings(left, right, left_actions, right_actions)
  end

  def contradictory_action_warnings(left, right, left_actions, right_actions)
    CONTRADICTORY_ACTION_PAIRS.filter_map do |a, b|
      next unless (left_actions.key?(a) && right_actions.key?(b)) ||
                  (left_actions.key?(b) && right_actions.key?(a))

      conflict_finding(left, right, 'contradictory_actions', actions: [a, b])
    end
  end

  def conflicting_value_warnings(left, right, left_actions, right_actions)
    SINGLE_VALUE_ACTIONS.filter_map do |action_name|
      left_params = left_actions[action_name]
      right_params = right_actions[action_name]
      next if left_params.nil? || right_params.nil?
      next if left_params.sort == right_params.sort

      conflict_finding(
        left, right, 'conflicting_action_values',
        action_name: action_name,
        left_values: left_params,
        right_values: right_params
      )
    end
  end

  def action_map(rule)
    Array(rule.actions).each_with_object({}) do |action, acc|
      next unless action.is_a?(Hash)

      name = action['action_name'].to_s
      next if name.blank?

      acc[name] = Array(action['action_params']).map(&:to_s)
    end
  end

  def conflict_finding(left, right, code, meta = {})
    # Attribute the warning to the rule being edited when there is one, so the UI
    # can show it inline instead of pointing at some unrelated rule. Identity
    # again, not id: an unsaved subject would otherwise match whichever side also
    # had no id.
    owner = @subject && right.equal?(@subject) ? right : left
    other = owner.equal?(left) ? right : left

    Finding.new(
      rule_id: owner.id,
      rule_name: owner.name,
      code: code,
      message_key: "automation_rules.lint.#{code}",
      meta: meta.merge(
        event_name: owner.event_name,
        other_rule_id: other.id,
        other_rule_name: other.name
      )
    )
  end
end
