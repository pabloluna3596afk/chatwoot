class Conversations::ActivityMessageJob < ApplicationJob
  queue_as :high

  def perform(conversation, message_params, captain_decision_key = nil)
    message = conversation.messages.create!(message_params)
    return unless captain_decision_key && ChatwootApp.enterprise?

    Captain::Decisions::Recorder.capture(conversation) do
      decision = conversation.captain_decisions.find_by(decision_key: captain_decision_key, anchor_message_id: nil)
      decision&.update!(anchor_message: message)
    end
  end
end
