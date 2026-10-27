class CopilotActionEvent < ApplicationRecord
  belongs_to :item, class_name: 'CopilotActionItem', inverse_of: :events
  belongs_to :account
  belongs_to :user

  validates :event, inclusion: { in: CopilotActionItem::EVENTS }
  validates :payload_snapshot, :metadata, exclusion: { in: [nil] }
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Copilot action events are append-only' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Copilot action events are append-only' }
end
