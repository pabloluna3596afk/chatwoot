# == Schema Information
#
# Table name: plans
#
#  id                 :bigint           not null, primary key
#  addon_agent_price  :decimal(10, 2)   default(0.0), not null
#  addon_bot_price    :decimal(10, 2)   default(0.0), not null
#  credit_unit_price  :decimal(10, 4)   default(0.0), not null
#  description        :string
#  display_order      :integer          default(0), not null
#  is_active          :boolean          default(TRUE), not null
#  is_default_trial   :boolean          default(FALSE), not null
#  is_public          :boolean          default(TRUE), not null
#  max_captain_assistants :integer      default(1), not null
#  max_documents      :integer          default(10), not null
#  max_emails_per_day :integer          default(0), not null
#  max_human_agents   :integer          default(3), not null
#  max_inboxes        :integer          default(1), not null
#  monthly_messages   :integer          default(0), not null
#  name               :string           not null
#  price_monthly      :decimal(10, 2)   default(0.0), not null
#  price_yearly       :decimal(10, 2)   default(0.0), not null
#  slug               :string           not null
#  storage_mb         :integer          default(100), not null
#  trial_days         :integer          default(0), not null
#  trial_messages     :integer          default(0), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Indexes
#
#  index_plans_on_is_default_trial  (is_default_trial) UNIQUE WHERE is_default_trial
#  index_plans_on_slug              (slug) UNIQUE
#

# ChatHub's own pricing/limit tiers — the single source of truth for what an
# account can use (Captain AI responses/documents, human agents, inboxes,
# outgoing email), replacing the split between Chatwoot Cloud's Stripe-driven
# plan config (JSON in InstallationConfig, see Enterprise::Billing::PlanConfiguration
# and Enterprise::Account::PlanUsageAndLimits — never applies self-hosted anyway).
#
# Deliberately a top-level, un-namespaced model — the SuperAdmin/Administrate
# sidebar resolves a resource's model class by convention from its route name
# ("plan".classify => "Plan"), and a namespaced class name breaks navigation
# rendering across all of SuperAdmin, not just this resource's own pages.
class Plan < ApplicationRecord
  has_many :accounts, dependent: :nullify, inverse_of: :plan

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  # DB partial unique index enforces this too; the validation just gives a
  # friendly SuperAdmin form error instead of a raw StatementInvalid.
  validates :is_default_trial, uniqueness: true, if: :is_default_trial?

  scope :active, -> { where(is_active: true) }
  scope :public_plans, -> { where(is_public: true) }
  scope :ordered, -> { order(:display_order, :price_monthly) }
end
