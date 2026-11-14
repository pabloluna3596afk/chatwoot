class Captain::Pilot
  FLAG = 'captain_pilot'.freeze

  def self.enabled?(account)
    account.present? && account.feature_enabled?(FLAG)
  end
end
