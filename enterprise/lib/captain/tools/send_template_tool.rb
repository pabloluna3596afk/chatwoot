class Captain::Tools::SendTemplateTool < Captain::Tools::BaseMessagingTool
  description 'Send the customer an approved message template (a paid WhatsApp message). Use only a name and language from ' \
              'template_catalog. It does not send right away: the template goes out as your reply to this message, so ' \
              'do not write it yourself and never promise it unless this tool says it is prepared. The values of its variables ' \
              'are filled in by the system, you do not provide them.'
  param :template_name, type: 'string', desc: 'The name of the template, from template_catalog'
  param :language, type: 'string', desc: 'The language code of the template, from template_catalog'

  def perform(tool_context, template_name:, language:)
    conversation, error = conversation_for(tool_context)
    return error if error
    return translate('errors.invalid_params') if template_name.blank? || language.blank?

    request = Captain::Messaging::Request.new(kind: 'template', resource: { name: template_name.to_s, language: language.to_s })
    prepare(conversation, tool_context, request)
  end
end
