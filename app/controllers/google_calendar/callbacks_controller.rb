class GoogleCalendar::CallbacksController < ApplicationController
  include GoogleCalendar::IntegrationHelper

  def show
    authorize_initiator!

    return render plain: I18n.t('google_calendar.oauth.cancelled'), status: :unprocessable_entity if params[:code].blank? || params[:error].present?

    tokens = Integrations::GoogleCalendar::Oauth.exchange_code(params[:code])
    persist_connection(tokens)
    redirect_to calendars_redirect_uri
  rescue GoogleCalendar::IntegrationHelper::InvalidState, ActiveRecord::RecordNotFound
    render plain: I18n.t('google_calendar.oauth.invalid_state'), status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("Google Calendar callback failed: #{e.class}")
    render plain: I18n.t('google_calendar.oauth.failed'), status: :unprocessable_entity
  end

  private

  attr_reader :account

  def authorize_initiator!
    state = verify_google_calendar_token(params[:state])
    @account = Account.find(state.fetch('sub'))
    @initiating_user = account.account_users.find_by(user_id: state.fetch('user_id'), role: :administrator)&.user
    raise GoogleCalendar::IntegrationHelper::InvalidState unless @initiating_user && account.active?
  end

  def persist_connection(tokens)
    access_token = tokens['access_token']
    raise ArgumentError, 'Missing Google access token' if access_token.blank?

    profile = Integrations::GoogleCalendar::Oauth.fetch_profile(access_token)
    email = profile[:email]
    raise ArgumentError, 'Missing Google account email' if email.blank?

    connection = account.calendar_connections.find_or_initialize_by(provider: :google, email: email)
    refresh_token = tokens['refresh_token'].presence || connection.refresh_token
    raise ArgumentError, 'Missing Google refresh token' if refresh_token.blank?

    expires_in = tokens['expires_in'].to_i
    expires_in = 3600 if expires_in.zero?

    connection.assign_attributes(
      refresh_token: refresh_token,
      access_token: access_token,
      access_token_expires_at: Time.current.utc + expires_in.seconds,
      scopes: Array(tokens['scope'].to_s.split),
      is_active: true,
      connected_by: @initiating_user,
      display_name: profile[:name].presence || Integrations::GoogleCalendar::Oauth.name_from_id_token(tokens['id_token'])
    )
    connection.save!
    @connection = connection
  end

  def calendars_redirect_uri
    "#{ENV.fetch('FRONTEND_URL', nil)}/app/accounts/#{account.id}/settings/integrations/calendars?setup=#{@connection.id}"
  end
end
