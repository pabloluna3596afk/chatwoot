class CalendarTemplateResource < ApplicationRecord
  belongs_to :account
  belongs_to :whatsapp_template_draft, optional: true

  enum :function, { confirmation: 'confirmation', cancellation: 'cancellation', reminder: 'reminder' }, prefix: true
  enum :status, { pending: 'pending', linked: 'linked', incompatible: 'incompatible' }, prefix: true

  validates :function, :template_name, :language, :status, presence: true
  validates :language, inclusion: { in: %w[es en] }
  validates :function, uniqueness: { scope: [:account_id, :language, :waba_id] }
  validates :waba_id, presence: true, if: -> { waba_id == '' || status_linked? }
  validates :remote_template_id, :linked_at, presence: true, if: :status_linked?
  validate :draft_ownership
  validate :snapshot_shape

  private

  def draft_ownership
    return unless whatsapp_template_draft
    return if whatsapp_template_draft.account_id == account_id && whatsapp_template_draft.waba_id == waba_id

    errors.add(:whatsapp_template_draft, :invalid)
  end

  def snapshot_shape
    errors.add(:contract_snapshot, :invalid) unless contract_snapshot.is_a?(Hash)
    return unless status_linked?
    return if contract_snapshot.is_a?(Hash) && contract_snapshot['version'].present? && contract_snapshot['variables'].is_a?(Array) &&
              contract_snapshot['actions'].is_a?(Hash)

    errors.add(:contract_snapshot, :invalid)
  end
end
