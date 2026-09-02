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

    warnings.concat(AutomationRules::CrossRuleLinter.new(rules: @rules, subject: @subject).perform)

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

    conditions.each_cons(2).with_index.filter_map do |(left, right), index|
      next unless contradictory_pair?(left, right)

      finding(
        rule, 'impossible_and',
        attribute_key: left['attribute_key'].to_s,
        left_values: normalize_values(left['values']),
        right_values: normalize_values(right['values']),
        condition_index: index
      )
    end
  end

  def contradictory_pair?(left, right)
    return false unless left['query_operator'].to_s.casecmp('and').zero?
    return false unless same_equality_attribute?(left, right)

    left_vals = normalize_values(left['values'])
    right_vals = normalize_values(right['values'])
    return false if left_vals.empty? || right_vals.empty?

    unsatisfiable?(left, right, left_vals, right_vals)
  end

  def same_equality_attribute?(left, right)
    key = left['attribute_key'].to_s
    return false if key.blank? || key != right['attribute_key'].to_s

    EQUALITY_OPS.include?(left['filter_operator'].to_s) &&
      EQUALITY_OPS.include?(right['filter_operator'].to_s)
  end

  # equal_to + equal_to with disjoint sets is impossible.
  # equal_to + not_equal_to over the same single value is impossible too.
  def unsatisfiable?(left, right, left_vals, right_vals)
    operator = left['filter_operator'].to_s
    return left_vals.intersect?(right_vals) unless operator == right['filter_operator'].to_s

    operator == 'equal_to' && !left_vals.intersect?(right_vals)
  end

  def unknown_attribute_errors(rule, conditions)
    standard = rule.conditions_attributes.to_set(&:to_s)

    conditions.filter_map do |condition|
      key = condition['attribute_key'].to_s
      next if key.blank? || standard.include?(key)

      custom_type = condition['custom_attribute_type'].to_s
      next if known_custom_keys(custom_type).include?(key)

      finding(
        rule, 'unknown_attribute_key',
        attribute_key: key,
        custom_attribute_type: custom_type.presence
      )
    end
  end

  # An unset type means the editor did not say which side the attribute lives on,
  # so accept a match on either rather than calling a real attribute unknown.
  def known_custom_keys(custom_type)
    case custom_type
    when 'contact_attribute' then known_keys_for(:contact_attribute)
    when 'conversation_attribute' then known_keys_for(:conversation_attribute)
    else known_keys_for(:contact_attribute) | known_keys_for(:conversation_attribute)
    end
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
                                             .to_set(&:to_s)
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
end
