# Call at the effective action, within its existing transaction. No raw model/tool payload crosses this boundary.
class Captain::Decisions::Action
  def self.record(conversation:, assistant:, **attributes)
    Captain::Decisions::Recorder.record(
      conversation: conversation, assistant: assistant, outcome: 'completed', **attributes
    ) do
      { reason_text: I18n.t("captain.decisions.#{attributes.fetch(:reason_code)}", locale: conversation.account.locale) }
    end
  end
end
