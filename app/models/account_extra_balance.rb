class AccountExtraBalance < ApplicationRecord
  SOURCES = %w[purchase courtesy manual].freeze
  VALIDITY = 90.days

  belongs_to :account
  belongs_to :extra_pack, optional: true

  validates :bucket, inclusion: { in: ExtraPack::BUCKETS }
  validates :source, inclusion: { in: SOURCES }
  validates :expires_at, presence: true
  validates :units_total, numericality: { only_integer: true, greater_than: 0 }
  validates :units_remaining, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: :units_total }
  validates :external_reference, uniqueness: true, allow_nil: true
  validate :matching_pack_bucket

  # Expiration is evaluated at every read/reservation, including between daily jobs.
  scope :available, -> { where('expires_at > ?', Time.current).where('units_remaining > 0') }
  scope :expiring_first, -> { order(:expires_at, :id) }

  private

  def matching_pack_bucket
    errors.add(:bucket, :invalid) if extra_pack && extra_pack.bucket != bucket
  end
end
