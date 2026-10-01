module Enterprise::Conversations::CaptainFollowupJob
  def perform
    super

    Captain::Followup::Dispatcher.new.perform
  end
end
