# What Meta says about a flow on ONE WABA: the Meta flow id, its status, the errors Meta (or our own check) found, and the
# version. Two numbers on the same WABA share the row. See Whatsapp::Flows::PublishToMetaService.
class WhatsappFlowPublication < ApplicationRecord
  VALID_STATUSES = %w[draft published deprecated blocked throttled].freeze

  belongs_to :whatsapp_flow
  belongs_to :account

  validates :waba_id, presence: true, format: { with: /\A\d+\z/ }
  validates :whatsapp_flow_id, uniqueness: { scope: :waba_id }
  validates :status, inclusion: { in: VALID_STATUSES }

  scope :by_waba, ->(waba_id) { where(waba_id: waba_id) }
  scope :by_status, ->(status_val) { where(status: status_val) }
  scope :with_errors, -> { where("validation_errors <> '[]'::jsonb") }

  def published_in_meta?
    status == 'published'
  end
end
