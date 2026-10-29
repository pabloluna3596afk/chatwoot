class AccountFeatureOverride < ApplicationRecord
  belongs_to :account
  belongs_to :created_by, class_name: 'User'

  validates :feature_key, inclusion: { in: Plan::ACCOUNT_FEATURES_BY_KEY.keys }, uniqueness: { scope: :account_id }
  validates :reason, presence: true
  validates :enabled, inclusion: { in: [true, false] }

  after_commit :sync_account_features

  scope :current, -> { where('expires_at IS NULL OR expires_at > ?', Time.current) }

  private

  def sync_account_features
    account.reset_feature_override_cache!
    Plans::AccountFeatureSync.call(account) if account.persisted? && account.plan_id.present?
  end
end
