class Api::V1::Accounts::Captain::AgentSessionsController < Api::V1::Accounts::BaseController
  before_action :set_message
  before_action :authorize_conversation

  def show
    @agent_session = Current.account.captain_agent_sessions.find_by(result_type: 'Message', result_id: @message.id,
                                                                    subject_type: 'Conversation', subject_id: @message.conversation_id)
    return head :not_found if @agent_session.blank?

    @citations = Current.account.captain_documents.where(assistant_id: @agent_session.assistant_id, id: @agent_session.cited_document_ids)
    @used_faqs = Current.account.captain_assistant_responses.approved.where(
      assistant_id: @agent_session.assistant_id, id: @agent_session.used_faq_ids,
      documentable_type: 'User'
    )
    @scenario_titles = Captain::Scenario.where(
      account_id: Current.account.id, assistant_id: @agent_session.assistant_id, id: @agent_session.scenario_ids
    ).pluck(:id, :title).to_h
  end

  private

  def set_message
    @message = Current.account.messages.find(params[:id])
  end

  def authorize_conversation
    unless Current.user.is_a?(User) && Current.account_user && Captain::Decisions::Access.visible_anchor?(Current.user, @message)
      return head :unauthorized
    end

    authorize @message.conversation, :show?
  end
end
