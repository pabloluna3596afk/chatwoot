class Captain::Messaging::LegacyEntryConverter
  def initialize(assistant, entry)
    @assistant = assistant
    @entry = entry
    @inbox = assistant.account.inboxes.find(entry.fetch('inbox_id'))
    @waba_id = @inbox.channel.provider_config.to_h['business_account_id'].to_s
  end

  def perform
    notes, params = template_settings
    @entry['mode'] = 'auto'
    @entry['notes'] = notes.merge(flow_notes)
    @entry['params'] = params
    @entry['included_marketing'] = []
    @entry['reviewed'] = Captain::Messaging::Review.new(@assistant, @inbox).activation_snapshot
    @entry.delete('templates')
    @entry.delete('flows')
  end

  private

  def template_settings
    result = [{}, {}]
    return result if @waba_id.blank?

    Array(@entry['templates']).each { |template| add_template_settings(result, template) }
    result
  end

  def add_template_settings(result, template)
    key = Captain::Messaging::TemplateKey.for(@waba_id, template)
    result[0]["template:#{key}"] = template['purpose'] if template['purpose'].present?
    result[1][key] = template['processed_params'] if template['processed_params'].present?
  end

  def flow_notes
    return {} if @waba_id.blank?

    Array(@entry['flows']).each_with_object({}) do |flow, notes|
      next if flow['purpose'].blank?

      notes["flow:#{@waba_id}:#{flow['flow_id']}"] = flow['purpose']
    end
  end
end
