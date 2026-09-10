class Api::V1::Accounts::AgentBotsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :agent_bot, except: [:index, :create]

  def index
    @agent_bots = AgentBot.accessible_to(Current.account)
  end

  def show; end

  def create
    @agent_bot = Current.account.agent_bots.create!(permitted_params.except(:avatar_url))
    process_avatar_from_url
  end

  def update
    @agent_bot.update!(permitted_params.except(:avatar_url))
    process_avatar_from_url
  end

  def avatar
    @agent_bot.avatar.purge if @agent_bot.avatar.attached?
    @agent_bot
  end

  # Never a hard delete: destroying an AgentBot nulls out the sender on every
  # message it sent and the assignee on every conversation it was handling
  # (see the dependent: :nullify associations on AgentBot) — deactivating
  # keeps that history intact and just stops it from taking on anything new.
  def destroy
    @agent_bot.update!(active: false)
    head :ok
  end

  def activate
    @agent_bot.update!(active: true)
    head :ok
  end

  def reset_access_token
    @agent_bot.access_token.regenerate_token
    @agent_bot.reload
  end

  def reset_secret
    @agent_bot.reset_secret!
  end

  def panel_ai_summary
    summary = PanelAi::AgentBotSummaryService.new(@agent_bot).call
    if summary
      render json: summary
    else
      render json: { available: false }, status: :ok
    end
  end

  private

  def agent_bot
    @agent_bot = AgentBot.accessible_to(Current.account).find(params[:id]) if params[:action] == 'show'
    @agent_bot ||= Current.account.agent_bots.find(params[:id])
  end

  def permitted_params
    params.permit(:name, :description, :outgoing_url, :avatar, :avatar_url, :bot_type, bot_config: {})
  end

  def process_avatar_from_url
    ::Avatar::AvatarFromUrlJob.perform_later(@agent_bot, params[:avatar_url]) if params[:avatar_url].present?
  end
end
