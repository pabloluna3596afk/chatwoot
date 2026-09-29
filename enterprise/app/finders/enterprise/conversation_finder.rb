module Enterprise::ConversationFinder
  def conversations_base_query
    query = super.includes(inbox: :captain_inbox)
    return query unless current_account.feature_enabled?('sla')

    query.includes(:applied_sla, :sla_events, inbox: :working_hours)
  end
end
