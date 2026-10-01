module Enterprise::Conversations::FilterService
  def base_relation
    super.includes(inbox: :captain_inbox)
  end
end
