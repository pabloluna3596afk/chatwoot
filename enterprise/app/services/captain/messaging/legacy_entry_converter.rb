class Captain::Messaging::LegacyEntryConverter
  def initialize(assistant, entry)
    @assistant = assistant
    @entry = entry
    @inbox = assistant.account.inboxes.find(entry.fetch('inbox_id'))
    @waba_id = @inbox.channel.provider_config.to_h['business_account_id'].to_s
  end

  def perform
    notes, params, marketing = template_settings
    @entry['mode'] = 'auto'
    @entry['notes'] = notes.merge(flow_notes)
    @entry['params'] = params
    @entry['included_marketing'] = marketing
    @entry['reviewed'] = Captain::Messaging::Review.new(@assistant, @inbox).activation_snapshot
    @entry.delete('templates')
    @entry.delete('flows')
  end

  private

  def template_settings
    result = [{}, {}, []]
    Array(@entry['templates']).each { |template| add_template_settings(result, template) }
    result
  end

  def add_template_settings(result, template)
    key = "#{@waba_id}:#{template['name']}|#{template['language']}"
    result[0]["template:#{key}"] = template['purpose'] if template['purpose'].present?
    result[1][key] = template['processed_params'] if template['processed_params'].present?
    result[2] << key if marketing_template?(template)
  end

  def marketing_template?(template)
    current = Array(@inbox.channel.message_templates).find do |item|
      item['name'] == template['name'] && item['language'].to_s.casecmp?(template['language'].to_s)
    end
    current && current['category'].to_s.upcase == 'MARKETING'
  end

  def flow_notes
    Array(@entry['flows']).each_with_object({}) do |flow, notes|
      next if flow['purpose'].blank?

      notes["flow:#{@waba_id}:#{flow['flow_id']}"] = flow['purpose']
    end
  end
end
