class Api::V1::Accounts::Contacts::ConversationsController < Api::V1::Accounts::Contacts::BaseController
  RESULTS_PER_PAGE = 50

  # Scoped to a conversation, this returns it with the ones created around it: the in-thread
  # navigation walks the whole history and never needs more than that.
  def index
    @conversations = if params[:conversation_id].present?
                       conversation_with_neighbours(params[:conversation_id])
                     else
                       sorted_conversations.limit(RESULTS_PER_PAGE)
                     end
  end

  private

  # The contact panel's sort picker (sort_by) uses the shared conversation sorter; without it, newest first.
  def sorted_conversations
    return permitted_conversations.order(created_at: :desc, id: :desc) if params[:sort_by].blank?

    Conversations::Sort.apply(permitted_conversations, params[:sort_by], account: Current.account)
  end

  def permitted_conversations
    conversations = Current.account.conversations.includes(
      :assignee, :contact, :taggings, :contact_inbox
    ).preload(
      inbox: :channel,
      ai_assignee: { avatar_attachment: [:blob] }
    ).where(contact_id: @contact.id)

    Conversations::PermissionFilterService.new(
      conversations,
      Current.user,
      Current.account
    ).perform
  end

  def conversation_with_neighbours(display_id)
    conversation = permitted_conversations.find_by!(display_id: display_id)

    [neighbour(conversation, :older), conversation, neighbour(conversation, :newer)].compact
  end

  def neighbour(conversation, direction)
    comparison = direction == :older ? '<' : '>'
    order = direction == :older ? :desc : :asc

    permitted_conversations
      .where("(conversations.created_at, conversations.id) #{comparison} (?, ?)", conversation.created_at, conversation.id)
      .order(created_at: order, id: order)
      .first
  end
end
