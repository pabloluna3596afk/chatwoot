# Brings the appointments Captain booked for an account in line with what Captain does today, for data that predates it
# or that a failure left half done (the booking whose reminders failed after the Google event existed):
# - a booking still "pending confirmation" is confirmed (the customer said yes in the chat);
# - the invite answer of the upcoming ones is read from Google;
# - upcoming bookings with no reminder rows get their reminders;
# - bookings whose Google event is gone are reported (never deleted here).
# It only reports unless `apply` is true. Run it with: rake captain:appointments:reconcile[ACCOUNT_ID] (APPLY=1 to write).
class Captain::AppointmentReconciler
  Result = Struct.new(:confirmed, :invitations, :reminders, :missing_in_google, :failed, keyword_init: true)

  def initialize(account, apply: false, log: nil)
    @account = account
    @apply = apply
    @log = log || ->(_line) {}
    @result = Result.new(confirmed: [], invitations: [], reminders: [], missing_in_google: [], failed: [])
  end

  def perform
    events.find_each do |event|
      reconcile(event)
    rescue StandardError => e
      @result.failed << event.id
      say("event #{event.id}: #{e.class} #{e.message}")
    end
    @result
  end

  private

  def events
    @account.calendar_events.kept.where(booking_source: 'ai').includes(:calendar_connection, :conversation)
  end

  def reconcile(event)
    confirm(event)
    return unless upcoming?(event)

    check_google(event)
    schedule_reminders(event)
  end

  def confirm(event)
    return unless event.appointment_status == 'pending_confirmation'

    @result.confirmed << event.id
    say("event #{event.id} (#{event.summary}): pending_confirmation -> confirmed")
    event.update!(appointment_status: 'confirmed') if @apply
  end

  def upcoming?(event)
    event.start_at.present? && event.start_at > Time.current
  end

  # One read of the Google event tells whether it still exists and what the customer answered to the invite.
  def check_google(event)
    google_event = service_for(event).google_event_for(event)
    return report_missing(event) if google_event['status'] == 'cancelled'

    status = Integrations::GoogleCalendar::EventService.invitation_status_from(google_event)
    return if status == event.invitation_status

    @result.invitations << event.id
    say("event #{event.id}: invitation #{event.invitation_status.inspect} -> #{status.inspect}")
    event.update!(invitation_status: status) if @apply
  rescue Integrations::GoogleCalendar::Client::Error => e
    raise unless [404, 410].include?(e.code.to_i)

    report_missing(event)
  end

  def report_missing(event)
    @result.missing_in_google << event.id
    say("event #{event.id} (#{event.summary}, #{event.start_at&.iso8601}): not in Google any more")
  end

  def schedule_reminders(event)
    conversation = event.conversation
    assistant = conversation&.inbox&.try(:captain_assistant)
    return if assistant.blank? || !assistant.appointments.any_reminder_enabled? || event.appointment_reminders.exists?

    @result.reminders << event.id
    say("event #{event.id}: no reminders yet -> scheduling")
    Captain::AppointmentReminders::Scheduler.schedule(event, assistant: assistant, conversation: conversation) if @apply
  end

  def service_for(event)
    @services ||= {}
    @services[event.calendar_connection_id] ||= Integrations::GoogleCalendar::EventService.new(
      account: @account, user: nil, connection: event.calendar_connection
    )
  end

  def say(line)
    @log.call("#{@apply ? '[apply]' : '[dry run]'} #{line}")
  end
end
