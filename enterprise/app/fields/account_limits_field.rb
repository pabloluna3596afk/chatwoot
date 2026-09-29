require 'administrate/field/base'

class AccountLimitsField < Administrate::Field::Base
  KEYS = %i[agents inboxes captain_responses captain_documents emails captain_storage].freeze

  # Manual per-account overrides only (raw `limits` jsonb) — nil where no
  # override is set. This is what the form binds as the submitted value, so
  # it must never contain plan-derived numbers or saving the form would
  # silently freeze them in as fake permanent overrides.
  def to_s
    defaults = KEYS.index_with { nil }
    overrides = (data.presence || {}).to_h.symbolize_keys.compact

    defaults.merge(overrides).to_json
  end

  # What the account is actually limited to right now if a given key has no
  # override — the assigned plan's numbers, or the same Cloud/global/max
  # fallback `Enterprise::Account::PlanUsageAndLimits` uses. Display-only.
  def effective
    return KEYS.index_with { nil }.to_json unless resource.respond_to?(:usage_limits)

    limits = resource.usage_limits
    {
      agents: limits[:agents],
      inboxes: limits[:inboxes],
      captain_responses: limits.dig(:captain, :responses, :total_count),
      captain_documents: limits.dig(:captain, :documents, :total_count),
      captain_storage: limits.dig(:captain, :storage, :total_count),
      emails: resource.respond_to?(:email_rate_limit) ? resource.email_rate_limit : nil
    }.to_json
  end
end
