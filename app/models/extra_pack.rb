class ExtraPack < ApplicationRecord
  BUCKETS = %w[captain_responses internal copilot].freeze

  has_many :account_extra_balances, dependent: :restrict_with_error

  validates :bucket, inclusion: { in: BUCKETS }
  validates :units, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :bucket }
  validates :price_usd, numericality: { greater_than: 0 }
  validates :display_order, numericality: { only_integer: true }

  scope :catalog, -> { where(active: true).order(:bucket, :display_order, :id) }
end
