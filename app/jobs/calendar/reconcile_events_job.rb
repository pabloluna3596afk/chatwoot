# Reconcile linked appointments independently of calendar views. The cursor keeps each job bounded
# while allowing all relevant rows to be visited, including human bookings and recently elapsed slots
# that may have moved forward in Google. Captain reminder creation remains Captain's responsibility.
class Calendar::ReconcileEventsJob < ApplicationJob
  queue_as :scheduled_jobs

  BATCH_SIZE = 100
  LOOKBACK = 1.day

  def perform(after_id = 0)
    events = CalendarEvent.kept.where('id > ? AND end_at >= ?', after_id, Time.current - LOOKBACK)
                          .where('contact_id IS NOT NULL OR conversation_id IS NOT NULL')
                          .order(:id).limit(BATCH_SIZE).includes(:account, :calendar_connection).to_a
    events.each { |event| reconcile(event) }
    self.class.perform_later(events.last.id) if events.length == BATCH_SIZE
  end

  private

  def reconcile(event)
    Integrations::GoogleCalendar::EventService.new(account: event.account, user: nil, connection: event.calendar_connection).reconcile!(event)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: event.account).capture_exception
  end
end
