# == Schema Information
#
# Table name: payphone_payments
#
#  id                     :bigint           not null, primary key
#  account_id             :bigint           not null
#  user_id                :bigint           not null
#  plan_id                :bigint           not null
#  client_transaction_id  :string           not null
#  amount                 :integer          not null
#  amount_without_tax     :integer          not null
#  amount_with_tax        :integer          not null
#  tax                    :integer          not null
#  base_cents             :integer          not null
#  tax_cents              :integer          not null
#  commission_cents       :integer          not null
#  currency               :string(3)        default("USD"), not null
#  status                 :string           default("pending"), not null
#  raw_response           :jsonb            default({}), not null
#  status_history         :jsonb            default([]), not null
#  card_token              :text
#  needs_invoice          :boolean          default(FALSE), not null
#  billing_tax_id_type    :string
#  billing_tax_id         :string
#  billing_name           :string
#  billing_email          :string
#  billing_phone          :string
#  billing_address        :string
#  payphone_transaction_id :string
#  authorization_code     :string
#  paid_at                :datetime
#  period_start           :datetime
#  period_end             :datetime
#  confirmed_at           :datetime
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#
class PayphonePayment < ApplicationRecord
  STATUSES = %w[pending approved cancelled failed expired].freeze
  TRANSITIONS = {
    'pending' => %w[approved cancelled failed expired],
    'approved' => [],
    'cancelled' => [],
    'failed' => [],
    'expired' => []
  }.freeze
  BILLING_TAX_ID_TYPES = %w[cedula ruc passport].freeze
  RAW_RESPONSE_KEYS = %w[status transactionId clientTransactionId authorizationCode message].freeze

  belongs_to :account
  belongs_to :user
  belongs_to :plan

  validates :client_transaction_id, presence: true, uniqueness: true, length: { maximum: 255 }
  validates :status, inclusion: { in: STATUSES }
  validates :currency, inclusion: { in: %w[USD] }
  validates :amount, :amount_without_tax, :amount_with_tax, :tax,
            :base_cents, :tax_cents, :commission_cents,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :billing_tax_id_type, inclusion: { in: BILLING_TAX_ID_TYPES }, allow_nil: true
  validate :amount_matches_breakdown
  validate :invoice_details_are_complete
  validate :approved_payment_has_period
  validate :payment_snapshot_is_immutable, on: :update
  validate :raw_response_is_allowlisted
  validate :payment_amounts_match_snapshot
  validate :status_change_has_audit_event, on: :update
  validate :new_payment_starts_pending, on: :create

  before_validation :normalize_invoice_details
  before_validation :initialize_status_history, on: :create

  def card_token
    Payphone::TokenCipher.decrypt(self[:card_token])
  end

  def card_token=(token)
    self[:card_token] = Payphone::TokenCipher.encrypt(token)
  end

  def transition_to!(new_status, attributes: {})
    new_status = new_status.to_s
    raise ArgumentError, "Invalid Payphone payment transition: #{status} -> #{new_status}" unless TRANSITIONS.fetch(status).include?(new_status)

    with_lock do
      previous_status = status
      self.status = new_status
      assign_attributes(attributes)
      self.status_history = status_history + [{
        'from' => previous_status,
        'to' => new_status,
        'at' => Time.current.iso8601
      }]
      save!
    end
  end

  private

  def amount_matches_breakdown
    return if [amount_without_tax, amount_with_tax, tax, commission_cents].any?(&:nil?)
    return if amount == amount_without_tax + amount_with_tax + tax + commission_cents

    errors.add(:amount, 'must equal the Payphone amount components')
  end

  def payment_amounts_match_snapshot
    return if [base_cents, amount_without_tax, amount_with_tax, tax, tax_cents].any?(&:nil?)
    return if amount_without_tax + amount_with_tax == base_cents && tax == tax_cents

    errors.add(:base, 'Payphone amounts must match the stored payment breakdown')
  end

  def normalize_invoice_details
    return if needs_invoice

    %i[billing_tax_id_type billing_tax_id billing_name billing_email billing_phone billing_address].each do |attribute|
      self[attribute] = nil
    end
  end

  def invoice_details_are_complete
    return unless needs_invoice

    %i[billing_tax_id_type billing_tax_id billing_name billing_email billing_phone billing_address].each do |attribute|
      errors.add(attribute, :blank) if self[attribute].blank?
    end
  end

  def approved_payment_has_period
    return unless status == 'approved'
    return if paid_at.present? && period_start.present? && period_end.present? && period_end > period_start

    errors.add(:base, 'approved payments require a paid date and period')
  end

  def status_change_has_audit_event
    return unless will_save_change_to_status?
    return if will_save_change_to_status_history?

    errors.add(:status_history, 'must record each status change')
  end

  def new_payment_starts_pending
    return if status == 'pending'

    errors.add(:status, 'must start as pending')
  end

  def payment_snapshot_is_immutable
    snapshot_attributes = %w[
      account_id user_id plan_id client_transaction_id amount amount_without_tax amount_with_tax tax
      base_cents tax_cents commission_cents currency needs_invoice billing_tax_id_type billing_tax_id
      billing_name billing_email billing_phone billing_address
    ]
    changed_snapshot = snapshot_attributes.select { |attribute| will_save_change_to_attribute?(attribute) }
    errors.add(:base, "payment snapshot is immutable: #{changed_snapshot.join(', ')}") if changed_snapshot.any?
  end

  def raw_response_is_allowlisted
    return if raw_response.is_a?(Hash) && (raw_response.keys.map(&:to_s) - RAW_RESPONSE_KEYS).empty?

    errors.add(:raw_response, 'contains fields that are not allowed')
  end

  def initialize_status_history
    self.status_history = [{ 'to' => 'pending', 'at' => Time.current.iso8601 }]
  end
end
