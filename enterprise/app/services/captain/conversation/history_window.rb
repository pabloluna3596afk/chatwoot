# Which messages of a long conversation still matter for the next reply.
class Captain::Conversation::HistoryWindow
  MAX_CONTEXT_MESSAGES = 40
  MESSAGES_BEFORE_BOUNDARY = 10
  LOOKBACK = 200
  MAX_IMAGE_MESSAGES = 3

  Result = Data.define(:messages, :image_message_ids, :total, :capped)

  def initialize(scope)
    @scope = scope
  end

  def perform
    recent = @scope.includes(:attachments).reorder(created_at: :desc, id: :desc).limit(LOOKBACK).to_a.reverse
    usable = recent.select { |message| !message.activity? || Captain::Conversation::EpisodeBoundary.resolved_activity?(message) }
    window = usable.last(MAX_CONTEXT_MESSAGES) & from_boundary(usable)
    latest_customer = usable.reverse.find(&:incoming?)
    window = [latest_customer, *window.drop(1)] if latest_customer && window.exclude?(latest_customer)
    total = @scope.count

    Result.new(messages: window, image_message_ids: image_ids(window), total: total, capped: window.size < usable.size || total > LOOKBACK)
  end

  private

  def from_boundary(usable)
    boundary = usable.rindex(&:activity?)
    return usable unless boundary

    usable[[boundary - MESSAGES_BEFORE_BOUNDARY, 0].max..]
  end

  def image_ids(window)
    window.select { |message| message.incoming? && message.attachments.any? { |attachment| attachment.file_type == 'image' } }
          .last(MAX_IMAGE_MESSAGES).map(&:id)
  end
end
