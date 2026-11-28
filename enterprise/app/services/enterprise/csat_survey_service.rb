module Enterprise::CsatSurveyService
  private

  # A conversation Captain closed for inactivity was never answered by the customer, so it gets no survey.
  # The survey goes out normally once the customer writes again and the conversation is resolved later.
  def should_send_csat_survey?
    super && !captain_closed_without_reply?
  end

  def captain_closed_without_reply?
    closed_at = conversation.additional_attributes&.dig(Captain::Followup::Reengager::STATE_KEY, 'closed_at')
    return false if closed_at.blank?

    conversation.messages.incoming.where(created_at: Time.zone.parse(closed_at)..).none?
  end
end
