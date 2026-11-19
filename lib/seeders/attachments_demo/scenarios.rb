class Seeders::AttachmentsDemo::Scenarios
  IMAGE_FILES = %w[normal.png photo.jpg animated.gif image.webp tall.png wide.png tiny.png receipt.png].freeze
  DOCUMENT_FILES = %w[quotation_marzo_version_final.pdf large.pdf contract.docx prices.xlsx documents.zip readme.txt].freeze
  EXPIRED_PATH = '/dashboard/images/attachments-demo-expired-404.png'.freeze

  def initialize(conversation, files)
    @conversation = conversation
    @files = files
    @position = 0
  end

  def perform!
    IMAGE_FILES.each do |file|
      media("#{file}:alone", [file])
      media("#{file}:caption", [file], content: "Adjuntos demo: #{file} con texto", message_type: :outgoing)
    end
    [2, 3, 4, 6, 7].each { |count| media("grid:#{count}", IMAGE_FILES.cycle.take(count), content: "Así quedó el local: #{count} imágenes") }
    DOCUMENT_FILES.each do |file|
      media("#{file}:alone", [file])
      media("#{file}:caption", [file], content: "Documento de demo: #{file}", message_type: :outgoing)
    end
    other_media
    replies
    email if @conversation.inbox.email?
    instagram if @conversation.inbox.instagram_direct?
  end

  private

  def message(scenario, **attributes)
    @position += 1
    source_id = "#{Seeders::AttachmentsDemo::MARKER}:#{@conversation.inbox_id}:#{scenario}"
    existing = @conversation.messages.find_by(source_id: source_id)
    record = existing || Seeders::AttachmentsDemo.insert_record(Message, message_attributes.merge(attributes).merge(source_id: source_id))
    puts "#{scenario.ljust(45)} -> message #{record.id}" # rubocop:disable Rails/Output -- CLI scenario table
    record
  end

  def message_attributes
    {
      account_id: @conversation.account_id, inbox_id: @conversation.inbox_id, conversation_id: @conversation.id,
      message_type: :incoming, content_type: :text, status: :sent, content_attributes: {}, additional_attributes: {},
      sender_type: 'Contact', sender_id: @conversation.contact_id, created_at: 2.hours.ago + @position.minutes
    }
  end

  def media(scenario, filenames, **attributes)
    if attributes[:message_type] == :outgoing
      attributes[:sender_type] = 'User'
      attributes[:sender_id] = @conversation.account.users.first&.id
    end
    record = message(scenario, **attributes)
    return record if record.attachments.exists?

    filenames.each { |filename| attach(record, filename) }
    record
  end

  def attach(record, filename)
    blob = @files.blob(filename)
    type = blob.content_type.split('/').first
    type = 'file' unless %w[image audio video].include?(type)
    meta = filename == 'voice.ogg' ? { is_voice_message: true, duration_seconds: 2 } : {}
    attachment = Seeders::AttachmentsDemo.insert_record(Attachment, account_id: record.account_id, message_id: record.id,
                                                                    file_type: type, extension: File.extname(filename).delete_prefix('.'),
                                                                    meta: meta, external_url: external_url(record, blob))
    attachment.file.attach(blob)
  end

  def external_url(record, blob)
    return unless record.incoming? && record.inbox.instagram_direct?

    Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
  end

  def other_media
    %w[audio.mp3 voice.ogg video.mp4].each do |file|
      media("#{file}:alone", [file])
      media("#{file}:caption", [file], content: "Demo multimedia: #{file}", message_type: :outgoing)
    end
    media('sticker', ['sticker.webp'], content_type: :sticker)
    structured('location', :location, coordinates_lat: -0.1807, coordinates_long: -78.4678,
                                      fallback_title: 'Quito · ubicación de demo', external_url: 'https://maps.google.com/?q=-0.1807,-78.4678')
    structured('contact', :contact, fallback_title: '+999000000001', meta: { first_name: 'María', last_name: 'Demo' })
    media('private-note', ['receipt.png', 'quotation_marzo_version_final.pdf'], content: 'Nota privada de demo', private: true,
                                                                                message_type: :outgoing)
    media('failed-upload', ['normal.png'], content: 'Adjunto de demo: fallo simulado', message_type: :outgoing,
                                           status: :failed, content_attributes: { external_error: 'DEMO: upload failed (simulated)' })
    structured('expired-image', :image, external_url: EXPIRED_PATH)
  end

  def structured(scenario, type, **attributes)
    record = message(scenario)
    return if record.attachments.exists?

    Seeders::AttachmentsDemo.insert_record(Attachment, attributes.merge(account_id: record.account_id, message_id: record.id, file_type: type))
  end

  def replies
    text = message('text-original', content: 'Texto original para responder')
    { 'image' => 'normal.png:alone', 'file' => 'quotation_marzo_version_final.pdf:alone', 'text' => 'text-original' }.each do |type, scenario|
      source_id = "#{Seeders::AttachmentsDemo::MARKER}:#{@conversation.inbox_id}:#{scenario}"
      original = type == 'text' ? text : @conversation.messages.find_by!(source_id: source_id)
      message("reply:#{type}", content: "Recibido, gracias (#{type})", message_type: :outgoing,
                               sender_type: 'User', sender_id: @conversation.account.users.first&.id,
                               content_attributes: { in_reply_to: original.id, in_reply_to_external_id: original.source_id })
    end
  end

  # Mirror MailboxInlineAttachmentHelper: CID MIME part -> stored blob URL in the
  # rendered HTML, not a duplicate attachment chip. Retain the original MIME as well.
  def email
    existing = @conversation.messages.find_by('source_id LIKE ?', '%:email:cid-and-three-files')
    return message('email:cid-and-three-files') if existing&.additional_attributes&.key?('attachments_demo_mime')

    blob = @files.blob('receipt.png')
    url = Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
    original = '<p>Comprobante inline y tres documentos.</p><img src="cid:receipt@attachments.demo">'
    email = { subject: 'Adjuntos demo · inline CID', from: ['demo@example.invalid'], to: ['inbox@example.invalid'],
              html_content: { full: original.sub('cid:receipt@attachments.demo', url), reply: original.sub('cid:receipt@attachments.demo', url) },
              text_content: { full: 'Comprobante inline y tres documentos.', reply: 'Comprobante inline y tres documentos.' } }
    record = media('email:cid-and-three-files', %w[quotation_marzo_version_final.pdf contract.docx prices.xlsx],
                   content: 'Comprobante inline y tres documentos.', content_type: :incoming_email, content_attributes: { email: email })
    return if record.additional_attributes['attachments_demo_mime']

    store_mime(record, blob, original)
  end

  def store_mime(record, blob, original)
    mime = mime_message(original)
    blob.open { |io| mime.attachments.inline['receipt.png'] = { mime_type: 'image/png', content: io.read } }
    mime.attachments['receipt.png'].content_id = '<receipt@attachments.demo>'
    record.attachments.each do |attachment|
      attachment.file.blob.open { |io| mime.attachments[attachment.file.filename.to_s] = io.read }
    end
    # Bypass Message's update callbacks too (the MIME source is for repeatable review).
    record.update_columns(additional_attributes: { attachments_demo_mime: mime.to_s }) # rubocop:disable Rails/SkipsModelValidations -- no delivery callbacks
  end

  def mime_message(original)
    Mail.new do
      from 'demo@example.invalid'
      to 'inbox@example.invalid'
      subject 'Adjuntos demo · inline CID'
      html_part do
        content_type 'text/html'
        body original
      end
    end
  end

  def instagram
    structured('instagram:story-mention', :story_mention, external_url: EXPIRED_PATH)
    structured('instagram:reel', :ig_reel, external_url: EXPIRED_PATH)
  end
end
