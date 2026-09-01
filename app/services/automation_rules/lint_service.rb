# frozen_string_literal: true

# Validates automation rules before they are saved, and flags rules that fight
# each other at runtime.
#
# Two severities, deliberately different in consequence:
#   errors   -> the rule can never fire (impossible condition, unknown attribute).
#               These block the save: keeping them would be dead config.
#   warnings -> the rule fires, but another active rule on the same trigger does
#               something contradictory. These do NOT block: two rules on one
#               trigger is sometimes exactly what you want, so this is a heads-up,
#               not a verdict.
#
# Mirrors BusinessRules::LintService in shape (Result/Error structs, message_key
# for i18n on the client) so both linters read the same way.
class AutomationRules::LintService
  Result = Struct.new(:ok?, :errors, :warnings, keyword_init: true)
  Finding = Struct.new(:rule_id, :rule_name, :code, :message_key, :meta, keyword_init: true)

  EQUALITY_OPS = %w[equal_to not_equal_to].freeze

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

  # @param account [Account]
  # @param rules [Array<AutomationRule>] rules to lint (usually all of the account's)
  # @param subject [AutomationRule, nil] when linting a single rule being saved,
  #   findings for other rules are suppressed — you only want feedback on yours.
  def initialize(account:, rules:, subject: nil)
    @account = account
    @rules = Array(rules)
    @subject = subject
  end

  def perform
    errors = []
    warnings = []

    linted = @subject ? [@subject] : @rules
    linted.each do |rule|
      errors.concat(lint_rule(rule))
    end

    warnings.concat(cross_rule_warnings)

    Result.new(ok?: errors.empty?, errors: errors, warnings: warnings)
  end

  private

  def lint_rule(rule)
    conditions = normalized_conditions(rule)
    findings = []
    findings.concat(impossible_and_errors(rule, conditions))
    findings.concat(unknown_attribute_errors(rule, conditions))
    findings.concat(empty_actions_errors(rule))
    findings.concat(schedule_errors(rule))
    findings
  end

  # Two conditions on the same attribute, joined by AND, both equality, with no
  # overlapping values — no record can ever satisfy both.
  def impossible_and_errors(rule, conditions)
    return [] if conditions.size < 2

    findings = []
    conditions.each_cons(2).with_index do |(left, right), index|
      next unless left['query_operator'].to_s.casecmp('and').zero?

      key = left['attribute_key'].to_s
      next if key.blank? || key != right['attribute_key'].to_s
      next unless EQUALITY_OPS.include?(left['filter_operator'].to_s)
      next unless EQUALITY_OPS.include?(right['filter_operator'].to_s)

      left_vals = normalize_values(left['values'])
      right_vals = normalize_values(right['values'])
      next if left_vals.empty? || right_vals.empty?

      # equal_to + equal_to with disjoint sets is impossible.
      # equal_to + not_equal_to over the same single value is impossible too.
      impossible =
        if left['filter_operator'].to_s == right['filter_operator'].to_s
          left['filter_operator'].to_s == 'equal_to' && (left_vals & right_vals).empty?
        else
          (left_vals & right_vals).any?
        end
      next unless impossible

      findings << finding(
        rule, 'impossible_and',
        attribute_key: key,
        left_values: left_vals,
        right_values: right_vals,
        condition_index: index
      )
    end
    findings
  end

  def unknown_attribute_errors(rule, conditions)
    standard = rule.conditions_attributes.map(&:to_s).to_set
    findings = []

    conditions.each do |condition|
      key = condition['attribute_key'].to_s
      next if key.blank? || standard.include?(key)

      custom_type = condition['custom_attribute_type'].to_s
      known =
        case custom_type
        when 'contact_attribute' then known_keys_for(:contact_attribute)
        when 'conversation_attribute' then known_keys_for(:conversation_attribute)
        else known_keys_for(:contact_attribute) | known_keys_for(:conversation_attribute)
        end
      next if known.include?(key)

      findings << finding(
        rule, 'unknown_attribute_key',
        attribute_key: key,
        custom_attribute_type: custom_type.presence
      )
    end
    findings
  end

  def empty_actions_errors(rule)
    return [] if Array(rule.actions).any? { |a| a.is_a?(Hash) && a['action_name'].present? }

    [finding(rule, 'empty_actions')]
  end

  def schedule_errors(rule)
    return [] unless rule.event_name.to_s == 'time_triggered'

    schedule = rule.schedule.is_a?(Hash) ? rule.schedule : {}
    kind = schedule['kind'].presence || schedule[:kind]
    return [] if kind.present?

    [finding(rule, 'missing_schedule_kind')]
  end

  # ---- cross-rule ----------------------------------------------------------

  # Rules that fire on the same trigger and do contradictory things. Runtime
  # picks them up with no explicit order (AutomationRuleListener#current_account_rules
  # has no ORDER BY), so the effective winner is whichever the DB returns last —
  # unpredictable enough to be worth surfacing.
  def cross_rule_warnings
    active = candidate_rules.select { |r| r.active? && r.event_name.present? }
    return [] if active.size < 2

    warnings = []
    active.group_by(&:event_name).each_value do |group|
      next if group.size < 2

      group.combination(2) do |left, right|
        # Only the rule being saved is worth reporting on. Match by object
        # identity: a rule that is still unsaved has no id, so comparing ids
        # both missed the new rule entirely and paired unrelated unsaved rules
        # with each other through `nil == nil`.
        next if @subject && !(left.equal?(@subject) || right.equal?(@subject))

        warnings.concat(action_conflicts(left, right))
      end
    end
    warnings
  end

  # The rule being saved stands in for the version still in the database, so an
  # edit is checked as it will be, not as it was.
  def candidate_rules
    return @rules unless @subject

    others = @rules.reject { |r| r.equal?(@subject) || (@subject.id.present? && r.id == @subject.id) }
    others + [@subject]
  end

  def action_conflicts(left, right)
    left_actions = action_map(left)
    right_actions = action_map(right)
    warnings = []

    CONTRADICTORY_ACTION_PAIRS.each do |a, b|
      next unless (left_actions.key?(a) && right_actions.key?(b)) ||
                  (left_actions.key?(b) && right_actions.key?(a))

      warnings << conflict_finding(left, right, 'contradictory_actions', actions: [a, b])
    end

    SINGLE_VALUE_ACTIONS.each do |action_name|
      next unless left_actions.key?(action_name) && right_actions.key?(action_name)

      left_params = left_actions[action_name]
      right_params = right_actions[action_name]
      next if left_params.sort == right_params.sort

      warnings << conflict_finding(
        left, right, 'conflicting_action_values',
        action_name: action_name,
        left_values: left_params,
        right_values: right_params
      )
    end

    warnings
  end

  def action_map(rule)
    Array(rule.actions).each_with_object({}) do |action, acc|
      next unless action.is_a?(Hash)

      name = action['action_name'].to_s
      next if name.blank?

      acc[name] = Array(action['action_params']).map(&:to_s)
    end
  end

  # ---- helpers -------------------------------------------------------------

  def normalized_conditions(rule)
    Array(rule.conditions).select { |c| c.is_a?(Hash) }
  end

  def normalize_values(values)
    Array(values).flatten.compact.map { |v| v.to_s.downcase }
  end

  def known_keys_for(attribute_model)
    @known_keys ||= {}
    @known_keys[attribute_model] ||= @account.custom_attribute_definitions
                                             .where(attribute_model: attribute_model)
                                             .pluck(:attribute_key)
                                             .map(&:to_s)
                                             .to_set
  end

  def finding(rule, code, meta = {})
    Finding.new(
      rule_id: rule.id,
      rule_name: rule.name,
      code: code,
      message_key: "automation_rules.lint.#{code}",
      meta: meta
    )
  end

  def conflict_finding(left, right, code, meta = {})
    # Attribute the warning to the rule being edited when there is one, so the
    # UI can show it inline instead of pointing at some unrelated rule.
    owner = @subject && right.id == @subject.id ? right : left
    other = owner.id == left.id ? right : left
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
