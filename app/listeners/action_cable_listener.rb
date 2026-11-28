class ActionCableListener < BaseListener
  include Events::Types
  include ActionCableContactBroadcast

  def notification_created(event)
    notification, account, unread_count, count = extract_notification_and_account(event)
    tokens = [event.data[:notification].user.pubsub_token]
    broadcast(account, tokens, NOTIFICATION_CREATED, { notification: notification.push_event_data, unread_count: unread_count, count: count })
  end

  def notification_updated(event)
    notification, account, unread_count, count = extract_notification_and_account(event)
    tokens = [event.data[:notification].user.pubsub_token]
    broadcast(account, tokens, NOTIFICATION_UPDATED, { notification: notification.push_event_data, unread_count: unread_count, count: count })
  end

  def notification_deleted(event)
    notification_data = event.data[:notification_data]

    user = User.find_by(id: notification_data[:user_id])
    account = Account.find_by(id: notification_data[:account_id])
    return if user.blank? || account.blank?

    notification_finder = NotificationFinder.new(user, account)
    tokens = [user.pubsub_token]
    broadcast(account, tokens, NOTIFICATION_DELETED, {
                notification: { id: notification_data[:id] },
                unread_count: notification_finder.unread_count,
                count: notification_finder.count
              })
  end

  def account_cache_invalidated(event)
    account = event.data[:account]
    tokens = user_tokens(account, account.agents)

    broadcast(account, tokens, ACCOUNT_CACHE_INVALIDATED, {
                cache_keys: event.data[:cache_keys]
              })
  end

  def background_task_updated(event)
    account = event.data[:account]
    # Account-wide operational notices go to agents and admins. Linked routes still enforce their own permissions.
    broadcast(account, user_tokens(account, account.agents), BACKGROUND_TASK_UPDATED, { task: event.data[:task] })
  end

  def message_created(event)
    message, account = extract_message_and_account(event)
    conversation = message.conversation
    tokens = user_tokens(account, message_broadcast_members(conversation, message))

    broadcast_message_to_agents_and_contact(account, tokens, MESSAGE_CREATED, message)
  end

  def message_updated(event)
    message, account = extract_message_and_account(event)
    conversation = message.conversation
    tokens = user_tokens(account, message_broadcast_members(conversation, message))

    data = message.push_event_data.merge(previous_changes: event.data[:previous_changes])
    broadcast_message_to_agents_and_contact(account, tokens, MESSAGE_UPDATED, message, data)
  end

  def first_reply_created(event)
    message, account = extract_message_and_account(event)
    conversation = message.conversation
    tokens = user_tokens(account, conversation.inbox.members)

    broadcast(account, tokens, FIRST_REPLY_CREATED, message.push_event_data)
  end

  def conversation_created(event)
    conversation, account = extract_conversation_and_account(event)
    tokens = user_tokens(account, conversation.inbox.members)

    broadcast_conversation_to_agents_and_contact(account, tokens, CONVERSATION_CREATED, conversation)
  end

  def internal_task_created(event)
    internal_task, account = extract_internal_task_and_account(event)
    return unless account.feature_enabled?('internal_tasks')

    internal_task = load_internal_task_for_broadcast(internal_task.id)
    tokens = user_tokens(account, internal_task_agents(account, internal_task))

    broadcast(account, tokens, INTERNAL_TASK_CREATED, { internal_task: internal_task.push_event_data })
  end

  def internal_task_updated(event)
    internal_task, account = extract_internal_task_and_account(event)
    return unless account.feature_enabled?('internal_tasks')

    internal_task = load_internal_task_for_broadcast(internal_task.id, include_events: true)
    tokens = user_tokens(account, internal_task_agents(account, internal_task))

    broadcast(account, tokens, INTERNAL_TASK_UPDATED, { internal_task: internal_task.push_event_data(include_events: true) })
  end

  def internal_message_created(event)
    internal_message, account = extract_internal_message_and_account(event)
    return unless account.feature_enabled?('internal_chats')

    internal_message = InternalMessage.includes(:user, internal_conversation: :team).find(internal_message.id)
    tokens = user_tokens(account, internal_chat_agents(account, internal_message.internal_conversation))

    broadcast(account, tokens, INTERNAL_MESSAGE_CREATED, { internal_message: internal_message.push_event_data })
  end

  def conversation_bot_handoff(event)
    broadcast_to_inbox_members(event, CONVERSATION_BOT_HANDOFF)
  end

  def conversation_read(event)
    broadcast_to_inbox_members(event, CONVERSATION_READ)
  end

  def conversation_status_changed(event)
    conversation, account = extract_conversation_and_account(event)
    tokens = user_tokens(account, conversation.inbox.members)

    broadcast_conversation_to_agents_and_contact(account, tokens, CONVERSATION_STATUS_CHANGED, conversation)
  end

  def conversation_updated(event)
    conversation, account = extract_conversation_and_account(event)
    tokens = user_tokens(account, conversation.inbox.members)

    broadcast_conversation_to_agents_and_contact(account, tokens, CONVERSATION_UPDATED, conversation)
  end

  def conversation_unread_count_changed(event)
    account, inbox_members = ::Conversations::UnreadCounts::BroadcastScope.new(event).perform
    return if account.blank? || !account.feature_enabled?('conversation_unread_counts')

    tokens = user_tokens(account, inbox_members)

    broadcast(account, tokens, CONVERSATION_UNREAD_COUNT_CHANGED, {})
  end

  def conversation_typing_on(event)
    broadcast_typing_event(event, CONVERSATION_TYPING_ON)
  end

  def conversation_typing_off(event)
    broadcast_typing_event(event, CONVERSATION_TYPING_OFF)
  end

  def assignee_changed(event)
    # Model callbacks identify automatic assignment (auto-assignment or automation
    # rules) by performed_by. The V2 AssignmentService also dispatches an event with
    # user (the assigned agent, NOT the performer). Neither requires inferring
    # automation from a missing Current.user.
    automatic_assignment = [Inbox, AssignmentPolicy, AutomationRule].include?(event.data[:performed_by].class) || event.data[:user].present?
    broadcast_to_inbox_members(event, ASSIGNEE_CHANGED, automatic_assignment: automatic_assignment)
  end

  def team_changed(event)
    broadcast_to_inbox_members(event, TEAM_CHANGED)
  end

  def conversation_contact_changed(event)
    broadcast_to_inbox_members(event, CONVERSATION_CONTACT_CHANGED)
  end

  def contact_created(event)
    contact, account = extract_contact_and_account(event)
    broadcast(account, [account_token(account)], CONTACT_CREATED, contact.push_event_data)
  end

  def contact_updated(event)
    contact, account = extract_contact_and_account(event)
    broadcast(account, [account_token(account)], CONTACT_UPDATED, contact.push_event_data)
  end

  def contact_merged(event)
    contact, account = extract_contact_and_account(event)
    broadcast(account, [account_token(account)], CONTACT_MERGED, contact.push_event_data)
  end

  def contact_deleted(event)
    contact_data = event.data[:contact_data]
    account = Account.find_by(id: contact_data[:account_id])
    return if account.blank?

    broadcast(account, [account_token(account)], CONTACT_DELETED, contact_data)
  end

  def conversation_mentioned(event)
    conversation, account = extract_conversation_and_account(event)
    user = event.data[:user]

    broadcast(account, [user.pubsub_token], CONVERSATION_MENTIONED, conversation.push_event_data)
  end

  private

  def broadcast_to_inbox_members(event, event_name, **metadata)
    conversation, account = extract_conversation_and_account(event)

    broadcast(account, user_tokens(account, conversation.inbox.members), event_name, conversation.push_event_data.merge(metadata))
  end

  def account_token(account)
    "account_#{account.id}"
  end

  def broadcast_typing_event(event, event_name)
    conversation = event.data[:conversation]
    user = event.data[:user]
    widget_tokens, client_tokens = split_contact_tokens(typing_contact_inboxes(conversation, user))
    data = { conversation: conversation.push_event_data, user: user.push_event_data, is_private: event.data[:is_private] || false }

    broadcast(conversation.account, typing_user_tokens(conversation, user) + client_tokens, event_name, data,
              widget: { tokens: widget_tokens, data: data.merge(conversation: conversation.widget_push_event_data) })
  end

  # Web widget sessions get the widget payload.
  # Client API sessions retain their contact payload and public attribute filtering.
  def split_contact_tokens(contact_inboxes)
    widget_inboxes, client_inboxes = contact_inboxes.partition { |contact_inbox| contact_inbox.inbox.web_widget? }
    [widget_inboxes.filter_map(&:pubsub_token), client_inboxes.filter_map(&:pubsub_token)]
  end

  def inbox_user_tokens(conversation)
    user_tokens(conversation.account, conversation.inbox.members)
  end

  # Whoever is typing does not get their own typing event
  def typing_user_tokens(conversation, user)
    tokens = inbox_user_tokens(conversation)
    user.respond_to?(:pubsub_token) ? tokens - [user.pubsub_token] : tokens
  end

  def typing_contact_inboxes(conversation, user)
    return [] if user.is_a?(Contact) || user.push_event_data[:type] == 'captain_assistant'

    [conversation.contact_inbox]
  end

  def user_tokens(account, agents)
    agent_tokens = Array(agents).filter_map(&:pubsub_token)
    admin_tokens = account.administrators.pluck(:pubsub_token)
    (agent_tokens + admin_tokens).uniq
  end

  def message_contact_inboxes(conversation, message)
    return [] if message.private? || message.activity? || conversation.contact_inbox.nil?

    session_contact_inboxes(conversation.contact_inbox)
  end

  # A verified session also reaches the contact's other verified sessions, in any inbox that still exists
  def session_contact_inboxes(contact_inbox)
    return [contact_inbox] unless contact_inbox.hmac_verified?

    contact_inbox.contact.contact_inboxes.where(hmac_verified: true).where.associated(:inbox).includes(:inbox).to_a
  end

  def load_internal_task_for_broadcast(task_id, include_events: false)
    includes = [:created_by, :assigned_to, :team, :task_template, { conversation: :contact }]
    includes << { events: :user } if include_events
    InternalTask.includes(includes).find(task_id)
  end

  # Align with InternalTaskPolicy::Scope: admins via user_tokens; agents who
  # are assignee, on the task team, or when the task is an open unclaimed pool.
  def internal_task_agents(account, task)
    return account.agents if task.assigned_to_id.blank? && task.team_id.blank?

    agents = []
    agents << task.assigned_to if task.assigned_to
    agents.concat(task.team.members.to_a) if task.team
    agents.compact.uniq
  end

  # Align with InternalConversationPolicy::Scope: admins via user_tokens;
  # agents who are members of the room's team.
  def internal_chat_agents(_account, conversation)
    conversation.team&.members.to_a || []
  end

  def message_broadcast_members(conversation, message)
    members = conversation.inbox.members
    return members unless message.private?

    members.select do |agent|
      Conversations::PrivateNoteVisibility.allowed?(
        user: agent, message: message, conversation: conversation
      )
    end
  end

  # widget: { tokens:, data: } sends web widget sessions their payload in the same job
  def broadcast(account, tokens, event_name, data, widget: {})
    widget_tokens = widget[:tokens].to_a
    return if tokens.blank? && widget_tokens.blank?

    widget_options = {}
    widget_options = { widget_members: widget_tokens.uniq, widget_data: broadcast_payload(account, widget[:data]) } if widget_tokens.present?
    ::ActionCableBroadcastJob.perform_later(tokens.uniq, event_name, broadcast_payload(account, data), **widget_options)
  end

  def broadcast_payload(account, data)
    payload = data.merge(account_id: account.id)
    # So the frondend knows who performed the action.
    # Useful in cases like conversation assignment for generating a notification with assigner name.
    payload[:performer] = Current.user&.push_event_data if Current.user.present?
    payload
  end
end

ActionCableListener.prepend_mod_with('ActionCableListener')
