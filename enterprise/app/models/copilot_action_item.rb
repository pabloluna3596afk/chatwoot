class CopilotActionItem < ApplicationRecord
  STATUSES = %w[pending approved executed rejected expired failed].freeze
  EVENTS = %w[proposed edited approved rejected expired executed failed].freeze

  belongs_to :account
  belongs_to :user
  belongs_to :copilot_thread
  belongs_to :copilot_message, optional: true
  has_many :events, class_name: 'CopilotActionEvent', foreign_key: :item_id, dependent: :restrict_with_error,
                    inverse_of: :item

  validates :action, :target_type, :target_id, :payload_hash, :expires_at, :idempotency_key, presence: true
  validates :action, inclusion: { in: ->(_) { Captain::Copilot::ActionRegistry.all.map(&:action_name) } }
  validates :target_type, inclusion: { in: %w[Conversation Contact] }
  validates :status, inclusion: { in: STATUSES }
  validate :thread_owner_and_account
  validate :message_belongs_to_thread

  before_validation :set_account_and_owner
  after_commit :broadcast_action_item, on: [:create, :update]

  def push_event_data
    attributes.slice(
      'id', 'copilot_message_id', 'action', 'target_type', 'target_id', 'payload', 'status',
      'expires_at', 'result', 'error', 'created_at', 'updated_at'
    ).merge(
      copilot_thread_id: copilot_thread_id,
      target_name: target_record.try(:name) || target_record.try(:title)
    )
  end

  def expire_if_needed!
    with_lock do
      return unless pending? && expires_at <= Time.current

      update!(status: 'expired', decided_at: Time.current)
      record_event!('expired')
    end
  end

  def pending? = status == 'pending'

  def record_event!(event, metadata: {})
    CopilotActionEvent.create!(item: self, account: account, user: user, event: event,
                               payload_snapshot: payload, metadata: metadata)
  end

  private

  def target_record
    @target_record ||= if target_type == 'Conversation'
                         account.conversations.find_by(display_id: target_id)
                       else
                         account.contacts.find_by(id: target_id)
                       end
  end

  def set_account_and_owner
    self.account_id ||= copilot_thread&.account_id
    self.user_id ||= copilot_thread&.user_id
  end

  def thread_owner_and_account
    return if copilot_thread.blank?
    return if copilot_thread.account_id == account_id && copilot_thread.user_id == user_id

    errors.add(:copilot_thread, 'must belong to the proposal owner and account')
  end

  def message_belongs_to_thread
    return if copilot_message.blank? || copilot_message.copilot_thread_id == copilot_thread_id

    errors.add(:copilot_message, 'must belong to the proposal thread')
  end

  def broadcast_action_item
    Rails.configuration.dispatcher.dispatch(COPILOT_ACTION_ITEM_CHANGED, Time.zone.now, copilot_action_item: self)
  end
end
