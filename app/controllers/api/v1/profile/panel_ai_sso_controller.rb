# frozen_string_literal: true

class Api::V1::Profile::PanelAiSsoController < Api::BaseController
  # Authenticated: returns a one-time Panel AI SSO URL for the current user.
  # Only account administrators may open Panel AI.
  def create
    panel_url = ENV.fetch('PANEL_AI_PUBLIC_URL', '').to_s.chomp('/')
    if panel_url.blank?
      return render json: { error: 'PANEL_AI_PUBLIC_URL is not configured' }, status: :service_unavailable
    end

    user = Current.user || current_user
    unless administrator_of_requested_account?(user)
      return render json: { error: 'administrator role required' }, status: :forbidden
    end

    token = user.generate_sso_auth_token
    email = ERB::Util.url_encode(user.email)
    url = "#{panel_url}/login/sso?email=#{email}&sso_auth_token=#{token}"
    render json: { url: url }
  end

  private

  def administrator_of_requested_account?(user)
    return false unless user

    account_id = params[:account_id].presence || Current.account&.id
    return false if account_id.blank?

    user.account_users.find_by(account_id: account_id)&.administrator?
  end
end
