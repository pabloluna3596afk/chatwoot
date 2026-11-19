# == Schema Information
#
# Table name: captain_inboxes
#
#  id                   :bigint           not null, primary key
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  appointments_enabled :boolean          default(TRUE), not null
#  captain_assistant_id :bigint           not null
#  inbox_id             :bigint           not null
#
# Indexes
#
#  index_captain_inboxes_on_captain_assistant_id               (captain_assistant_id)
#  index_captain_inboxes_on_captain_assistant_id_and_inbox_id  (captain_assistant_id,inbox_id) UNIQUE
#  index_captain_inboxes_on_inbox_id                           (inbox_id)
#
class CaptainInbox < ApplicationRecord
  attr_reader :activation_notices

  belongs_to :captain_assistant, class_name: 'Captain::Assistant'
  belongs_to :inbox

  validates :inbox_id, uniqueness: true
  validates_with Captain::InboxAudienceValidator
  validate :captain_assistant_must_be_customer_visible
  before_update :cancel_completion_signals, if: :will_save_change_to_captain_assistant_id?
  before_destroy :cancel_completion_signals
  after_commit -> { inbox.update_account_cache }, on: [:create, :destroy]
  after_commit :snapshot_messaging_review, on: :create

  # Appointments run on this channel only when the assistant has them on and the channel's own
  # switch is on (the switch defaults to on, so channels inherit the assistant setting).
  def appointments_active?
    appointments_enabled && captain_assistant.appointments.enabled?
  end

  private

  def cancel_completion_signals
    inbox.conversations.where("additional_attributes -> 'captain_completion' ->> 'status' IN (?)",
                              Captain::Conversation::CompletionSignal::ACTIVE_STATUSES).find_each do |conversation|
      conversation.with_lock do
        Captain::Conversation::CompletionSignal.cancel(conversation)
        conversation.save!
      end
    end
  end

  def snapshot_messaging_review
    @activation_notices = Captain::Messaging::Snapshotter.perform!(captain_assistant, inbox: inbox)
  end

  def captain_assistant_must_be_customer_visible
    errors.add(:captain_assistant, :invalid) if captain_assistant&.internal?
  end
end
