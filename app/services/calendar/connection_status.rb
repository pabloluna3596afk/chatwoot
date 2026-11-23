class Calendar::ConnectionStatus
  def self.active?(event, context:)
    return true if event.calendar_connection.reload.is_active?

    Rails.logger.info({ event: 'calendar_notice_paused', reason: 'connection_disconnected',
                        calendar_event_id: event.id, calendar_connection_id: event.calendar_connection_id, context: context }.to_json)
    false
  end
end
