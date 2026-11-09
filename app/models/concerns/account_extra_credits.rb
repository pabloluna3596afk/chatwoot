module AccountExtraCredits
  extend ActiveSupport::Concern

  included do
    has_many :account_extra_balances, dependent: :destroy_async
  end

  # Public grant contract includes both the optional pack and payment reference.
  # rubocop:disable Metrics/ParameterLists
  def grant_extra_balance!(bucket:, units:, source:, expires_at:, extra_pack: nil, external_reference: nil)
    raise ArgumentError, 'units must be a positive integer' unless units.is_a?(Integer) && units.positive?

    with_lock do
      if external_reference.present?
        existing = AccountExtraBalance.find_by(external_reference: external_reference)
        if existing
          raise ArgumentError, 'external_reference belongs to another account' if existing.account_id != id

          return existing
        end
      end
      account_extra_balances.create!(bucket: bucket, units_total: units, units_remaining: units, source: source,
                                     expires_at: expires_at, extra_pack: extra_pack, external_reference: external_reference)
    end
  end

  # rubocop:enable Metrics/ParameterLists

  def extra_available(bucket)
    account_extra_balances.available.where(bucket: bucket).sum(:units_remaining)
  end
end
