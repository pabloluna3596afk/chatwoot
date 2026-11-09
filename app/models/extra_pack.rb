class ExtraPack < ApplicationRecord
  BUCKETS = %w[captain_responses internal copilot].freeze

  has_many :account_extra_balances, dependent: :restrict_with_error

  validates :bucket, inclusion: { in: BUCKETS }
  validates :units, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :bucket }
  validates :price_usd, numericality: { greater_than: 0 }
  validates :display_order, numericality: { only_integer: true }

  scope :catalog, -> { where(active: true).order(:bucket, :display_order, :id) }

  # Fresh installations may load schema.rb instead of replaying data migrations.
  # Never replace a price or availability already edited in Super Admin.
  def self.seed_defaults!
    YAML.safe_load_file(Rails.root.join('db/seeds/extra_packs.yml')).each do |bucket, prices|
      prices.each_with_index do |(units, price), order|
        find_or_create_by!(bucket: bucket, units: units) do |pack|
          pack.price_usd = price
          pack.display_order = order
        end
      end
    end
  end
end
