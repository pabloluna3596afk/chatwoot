class WhatsappFlowPublication < ApplicationRecord
  belongs_to :whatsapp_flow
  belongs_to :account

  enum status: { draft: 'draft', published: 'published', deprecated: 'deprecated', blocked: 'blocked', throttled: 'throttled' }

  validates :whatsapp_flow_id, :account_id, :waba_id, presence: true
  validates :whatsapp_flow_id, uniqueness: { scope: :waba_id, message: 'should have only one publication per WABA' }
  validate :waba_id_format

  scope :by_waba, ->(waba_id) { where(waba_id: waba_id) }
  scope :by_status, ->(status_val) { where(status: status_val) }
  scope :publishable, -> { where(status: %w[draft published]) }
  scope :with_errors, -> { where.not(validation_errors: nil).where("validation_errors != '[]'") }

  def published_in_meta?
    status == 'published'
  end

  def has_validation_errors?
    validation_errors.present? && validation_errors.is_a?(Array) && validation_errors.any?
  end

  private

  def waba_id_format
    unless waba_id.match?(/^\d+$/)
      errors.add(:waba_id, 'must be a numeric string (Meta WABA ID format)')
    end
  end
end
