class WhatsappTemplateSubmission < ApplicationRecord
  IMMUTABLE_FIELDS = %w[whatsapp_template_draft_id account_id actor_id revision waba_id name language snapshot payload_digest].freeze
  STATUSES = %w[submitting submitted failed reconciling].freeze

  belongs_to :whatsapp_template_draft
  belongs_to :account
  belongs_to :actor, class_name: 'User', optional: true
  has_one_attached :media

  validates :revision, uniqueness: { scope: :whatsapp_template_draft_id }, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :waba_id, :name, :language, :payload_digest, presence: true
  validates :name, length: { maximum: 512 }
  validates :status, inclusion: { in: STATUSES }
  validate :snapshot_shape
  validate :immutable_snapshot, on: :update
  validate :account_ownership

  private

  def snapshot_shape
    errors.add(:snapshot, :invalid) unless snapshot.is_a?(Hash) && snapshot.present?
  end

  def immutable_snapshot
    errors.add(:base, 'La revisión enviada es inmutable.') if changed.intersect?(IMMUTABLE_FIELDS)
    errors.add(:request_payload, :invalid) if request_payload_changed? && request_payload_was.present?
  end

  def account_ownership
    errors.add(:account, :invalid) if whatsapp_template_draft.account_id != account_id
    errors.add(:actor, :invalid) if actor && will_save_change_to_actor_id? && !account.account_users.exists?(user_id: actor.id)
  end
end
