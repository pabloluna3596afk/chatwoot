class Payphone::AccountAccess
  def self.allowed?(account)
    return true if environment == 'production'

    account_ids.include?(account.id)
  end

  def self.environment
    InstallationConfig.find_by(name: 'PAYPHONE_ENVIRONMENT')&.value.to_s
  end

  def self.account_ids
    value = InstallationConfig.find_by(name: 'PAYPHONE_TEST_ACCOUNT_IDS')&.value.to_s
    value.split(',').filter_map { |id| Integer(id.strip, 10, exception: false) }
  end

  def self.valid_account_ids?(value)
    raw = value.to_s
    return true if raw.blank?

    ids = raw.split(',', -1).map(&:strip)
    ids.all? { |id| id.match?(/\A[1-9]\d*\z/) } &&
      Account.where(id: ids.map { |id| Integer(id, 10) }).count == ids.uniq.count
  end
end
