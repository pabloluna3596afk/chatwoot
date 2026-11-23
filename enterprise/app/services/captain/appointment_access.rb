# A contact's appointments on the configured resource, or kept in the assistant's authorized inboxes.
# Historical resource access does not depend on the current calendar selection or exclusive authorship.
class Captain::AppointmentAccess
  def initialize(assistant)
    @assistant = assistant
  end

  def upcoming(contact)
    scope = @assistant.account.calendar_events.kept.where(contact_id: contact.id)
    visible(scope).where('start_at < ? AND end_at > ?', 2.years.from_now, Time.current)
                  .includes(:created_by, :updated_by, :deleted_by, :contact, :conversation, :calendar_connection, activities: :user)
                  .order(:start_at).map { |record| Integrations::GoogleCalendar::EventService.payload_from_record(record) }
  end

  private

  def visible(scope)
    current = scope.where(calendar_connection_id: @assistant.appointments.calendar_connection_id,
                          external_calendar_id: @assistant.appointments.calendar_id)
    conversations = @assistant.account.conversations.where(inbox_id: @assistant.inboxes.select(:id))
    current.or(scope.where(conversation_id: conversations.select(:id)))
  end
end
