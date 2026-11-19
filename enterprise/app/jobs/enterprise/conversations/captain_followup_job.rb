module Enterprise::Conversations::CaptainFollowupJob
  def perform
    super

    Captain::ReviewCompletionSignalsJob.perform_now
    Captain::Followup::Dispatcher.new.perform
  end
end
