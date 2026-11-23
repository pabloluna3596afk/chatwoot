# Whether the assistant may still follow up an appointment. A stored booking actor pins the follow-up to the
# assistant that booked it; appointments without one keep the inbox's current assistant rule.
class Captain::AppointmentReminders::Eligibility
  def initialize(event, assistant, conversation, settings)
    @event = event
    @assistant = assistant
    @conversation = conversation
    @settings = settings
  end

  def enabled?(kind)
    @settings.reminder_enabled?(kind) && assistant_active?
  end

  private

  def assistant_active?
    return @assistant.appointments_active_in?(@conversation.inbox) if @event.booking_actor.blank?

    @settings.enabled? && booked_by_assistant? && @conversation.inbox.captain_inbox&.appointments_enabled?
  end

  def booked_by_assistant?
    @event.booking_actor['type'] == 'captain' && @event.booking_actor['id'] == @assistant.id
  end
end
