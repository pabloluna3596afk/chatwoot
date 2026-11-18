# Direct inserts deliberately bypass delivery, webhooks, automations and model callbacks.
# Only Active Storage attachments use normal writes; their blobs are already analyzed.
class Seeders::AttachmentsDemo
  PREFIX = 'Adjuntos demo · '.freeze
  MARKER = 'attachments-demo-v1'.freeze
  CHANNELS = {
    'API' => 'Channel::Api', 'WhatsApp Cloud' => 'Channel::Whatsapp', 'Email' => 'Channel::Email',
    'Web widget' => 'Channel::WebWidget', 'Telegram' => 'Channel::Telegram', 'Instagram' => 'Channel::Instagram',
    'Facebook' => 'Channel::FacebookPage', 'Twilio SMS' => 'Channel::TwilioSms'
  }.freeze

  def initialize(account:)
    @account = account
  end

  def perform!(reset: false)
    abort 'dev:attachments_demo is disabled in production' if Rails.env.production?

    # Serializes this seed and display-id allocation for the target account only.
    @account.with_lock do
      reset_messages if reset
      Dir.mktmpdir('attachments-demo') do |directory|
        files = Files.new(directory)
        CHANNELS.each do |name, channel_type|
          conversation = find_or_create_conversation(name, channel_type)
          puts "\n#{name}: /app/accounts/#{@account.id}/conversations/#{conversation.display_id}" # rubocop:disable Rails/Output -- CLI review links
          Scenarios.new(conversation, files).perform!
        end
      end
    end
  end

  def self.insert_record(model, attributes)
    model.find(model.insert!(attributes, returning: ['id']).rows.first.first) # rubocop:disable Rails/SkipsModelValidations -- no provider callbacks
  end

  private

  # Keep the owned inbox/contact/conversation identities, replacing only seeded messages.
  # Any messages added manually, and their attachments, are left untouched.
  def reset_messages
    conversations = @account.conversations.where("additional_attributes ->> 'attachments_demo' = ?", MARKER)
    messages = Message.where(conversation_id: conversations.select(:id), account_id: @account.id)
                      .where('source_id LIKE ?', "#{MARKER}:%")
    attachments = Attachment.where(message_id: messages.select(:id), account_id: @account.id)
    attachments.find_each { |attachment| attachment.file.purge if attachment.file.attached? }
    attachments.delete_all
    messages.delete_all
  end

  def find_or_create_conversation(name, channel_type)
    identifier = "#{MARKER}:#{name}"
    contact = @account.contacts.find_by(identifier: identifier) ||
              self.class.insert_record(Contact, account_id: @account.id, identifier: identifier, name: "#{PREFIX}#{name}")
    inbox = @account.inboxes.find_by(name: "#{PREFIX}#{name}") || create_inbox(name, channel_type)
    contact_inbox = find_or_create_contact_inbox(contact, inbox, identifier)
    @account.conversations.find_by(inbox_id: inbox.id, contact_id: contact.id) ||
      self.class.insert_record(Conversation, account_id: @account.id, inbox_id: inbox.id, contact_id: contact.id,
                                             contact_inbox_id: contact_inbox.id, uuid: SecureRandom.uuid,
                                             additional_attributes: { attachments_demo: MARKER },
                                             last_activity_at: Time.current)
  end

  def find_or_create_contact_inbox(contact, inbox, identifier)
    ContactInbox.find_by(contact_id: contact.id, inbox_id: inbox.id) ||
      self.class.insert_record(ContactInbox, contact_id: contact.id, inbox_id: inbox.id, source_id: identifier)
  end

  def create_inbox(name, channel_type)
    channel = self.class.insert_record(channel_type.constantize, channel_attributes(name).merge(account_id: @account.id))
    self.class.insert_record(Inbox, account_id: @account.id, name: "#{PREFIX}#{name}",
                                    channel_type: channel_type, channel_id: channel.id, enable_auto_assignment: false)
  end

  def channel_attributes(name)
    token = "attachments-demo-#{@account.id}"
    {
      'API' => { webhook_url: nil },
      'WhatsApp Cloud' => { phone_number: "+999#{@account.id.to_s.rjust(10, '0')}", provider: 'whatsapp_cloud',
                            provider_config: { api_key: token, phone_number_id: token, business_account_id: token } },
      'Email' => { email: "#{token}@example.invalid", forward_to_email: "forward-#{token}@example.invalid" },
      'Web widget' => { website_url: 'http://localhost', website_token: token, hmac_token: token },
      'Telegram' => { bot_token: token, bot_name: token },
      'Instagram' => { instagram_id: token, access_token: token, expires_at: 1.year.from_now },
      'Facebook' => { page_id: token, page_access_token: token, user_access_token: token },
      'Twilio SMS' => { account_sid: token, auth_token: token, messaging_service_sid: token, medium: 0 }
    }.fetch(name)
  end
end

require_relative 'attachments_demo/files'
require_relative 'attachments_demo/scenarios'
