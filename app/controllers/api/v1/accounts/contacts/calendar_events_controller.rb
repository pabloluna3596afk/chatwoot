# The upcoming appointments of a contact across all its conversations (the contact panel pins the next one).
class Api::V1::Accounts::Contacts::CalendarEventsController < Api::V1::Accounts::Contacts::BaseController
  MAX_EVENTS = 20

  def index
    Integrations::GoogleCalendar::EventService.refresh_upcoming_invitations(
      Current.account, Current.account.calendar_events.where(contact_id: @contact.id), user: Current.user
    )
    payloads = Integrations::GoogleCalendar::EventService.contact_payloads(
      Current.account, @contact.id, time_min: Time.current.iso8601, time_max: 2.years.from_now.iso8601
    )
    render json: { payload: payloads.first(MAX_EVENTS) }
  end
end
