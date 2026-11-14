class Captain::OpenAiMessageBuilderService
  MAX_ATTACHMENT_DESCRIPTIONS = 5
  MAX_FILENAME_LENGTH = 80
  ATTACHMENT_DESCRIPTIONS = {
    'video' => ['[The customer sent a video. You cannot watch it.]', '[A video was sent to the customer. You cannot watch it.]'],
    'contact' => ['[The customer shared a contact card.]', '[A contact card was shared with the customer.]']
  }.freeze
  GENERIC_ATTACHMENT_DESCRIPTIONS = [
    '[The customer sent an attachment you cannot open.]', '[An attachment you cannot open was sent to the customer.]'
  ].freeze

  pattr_initialize [:message!, { include_images: true }]

  # Extracts text and image URLs from multimodal content array (reverse of generate_content)
  def self.extract_text_and_attachments(content)
    return [content, []] unless content.is_a?(Array)

    text_parts = content.select { |part| part[:type] == 'text' }.pluck(:text)
    image_urls = content.select { |part| part[:type] == 'image_url' }.filter_map { |part| part.dig(:image_url, :url) }
    [text_parts.join(' ').presence, image_urls]
  end

  def generate_content
    parts = []
    text = Captain::Messaging::FlowAnswersContext.text_for(@message) || @message.content
    text = button_choice_content(text)
    parts << text_part(text) if text.present?
    parts.concat(attachment_parts(@message.attachments)) if @message.attachments.any?

    return '[Message without text]' if parts.blank?
    return parts.first[:text] if parts.one? && parts.first[:type] == 'text'

    parts
  end

  private

  def button_choice_content(text)
    return text unless @message.incoming? && @message.content_attributes['button_choice_changed'] == true

    annotation = I18n.t('captain.button_choice_changed', locale: @message.account.locale,
                                                         previous: @message.content_attributes['previous_button_choice'],
                                                         current: @message.content)
    "#{annotation}\n#{text}"
  end

  def text_part(text)
    { type: 'text', text: text }
  end

  def image_part(image_url)
    { type: 'image_url', image_url: { url: image_url } }
  end

  def attachment_parts(attachments)
    image_attachments = attachments.select { |attachment| attachment.file_type == 'image' }
    image_content = if !include_images && image_attachments.any?
                      [text_part('[Image sent earlier, not shown again]')]
                    else
                      image_parts(image_attachments)
                    end

    transcription = extract_audio_transcriptions(attachments)
    transcription_part = text_part(transcription) if transcription.present?

    descriptions = attachments.reject { |attachment| %w[image audio].include?(attachment.file_type) }
                              .first(MAX_ATTACHMENT_DESCRIPTIONS).map { |attachment| text_part(attachment_description(attachment)) }

    [image_content, transcription_part, descriptions].flatten.compact
  end

  def attachment_description(attachment)
    case attachment.file_type
    when 'file'
      file_description(attachment)
    when 'location'
      location_description(attachment)
    else
      ATTACHMENT_DESCRIPTIONS.fetch(attachment.file_type, GENERIC_ATTACHMENT_DESCRIPTIONS)[@message.incoming? ? 0 : 1]
    end
  end

  def file_description(attachment)
    name = attachment.file.attached? ? attachment.file.filename.to_s : attachment.fallback_title.to_s
    name = name.delete("\r\n\"[]").strip.first(MAX_FILENAME_LENGTH)
    named = name.present? ? " named \"#{name}\"" : ''
    if @message.incoming?
      "[The customer sent a file#{named}. You cannot open it.]"
    else
      "[A file#{named} was sent to the customer. You cannot open it.]"
    end
  end

  def location_description(attachment)
    lat = attachment.coordinates_lat
    long = attachment.coordinates_long
    coordinates = lat && long && !(lat.zero? && long.zero?) ? ": #{lat}, #{long}" : '.'
    subject = @message.incoming? ? 'The customer shared a location' : 'A location was shared with the customer'
    "[#{subject}#{coordinates}]"
  end

  def image_parts(image_attachments)
    image_attachments.each_with_object([]) do |attachment, parts|
      url = get_attachment_url(attachment)
      parts << image_part(url) if url.present?
    end
  end

  def get_attachment_url(attachment)
    return attachment.download_url if attachment.download_url.present?
    return attachment.external_url if attachment.external_url.present?

    attachment.file.attached? ? attachment.file_url : nil
  end

  def extract_audio_transcriptions(attachments)
    audio_attachments = attachments.select { |attachment| attachment.file_type == 'audio' }
    return '' if audio_attachments.blank?

    audio_attachments.map do |attachment|
      result = Messages::AudioTranscriptionService.new(attachment, assistant: true).perform
      result[:success] ? result[:transcriptions] : ''
    end.join
  end
end
