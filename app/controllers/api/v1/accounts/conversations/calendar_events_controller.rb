class Api::V1::Accounts::Conversations::CalendarEventsController < Api::V1::Accounts::Conversations::BaseController
  def index
    Integrations::GoogleCalendar::EventService.refresh_upcoming_invitations(
      Current.account, Current.account.calendar_events.where(conversation_id: @conversation.id), user: Current.user
    )
    render json: { payload: Integrations::GoogleCalendar::EventService.conversation_payloads(@conversation) }
  end
end
