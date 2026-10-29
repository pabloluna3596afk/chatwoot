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
  belongs_to :captain_assistant, class_name: 'Captain::Assistant'
  belongs_to :inbox

  validates :inbox_id, uniqueness: true
  validates_with Captain::InboxAudienceValidator
  validate :captain_assistant_must_be_customer_visible
  after_commit -> { inbox.update_account_cache }, on: [:create, :destroy]

  # Appointments run on this channel only when the assistant has them on and the channel's own
  # switch is on (the switch defaults to on, so channels inherit the assistant setting).
  def appointments_active?
    appointments_enabled && captain_assistant.appointments.enabled?
  end

  private

  def captain_assistant_must_be_customer_visible
    errors.add(:captain_assistant, :invalid) if captain_assistant&.internal?
  end
end
