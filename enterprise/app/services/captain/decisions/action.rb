# Call at the effective action, within its existing transaction. No raw model/tool payload crosses this boundary.
class Captain::Decisions::Action
  def self.record(conversation:, assistant:, reason_text: nil, **attributes)
    Captain::Decisions::Recorder.record(
      conversation: conversation, assistant: assistant, outcome: 'completed', **attributes
    ) do
      text = reason_text.presence&.first(Captain::Decision::REASON_TEXT_LIMIT)
      { reason_text: text || I18n.t("captain.decisions.#{attributes.fetch(:reason_code)}", locale: conversation.account.locale) }
    end
  end
end
