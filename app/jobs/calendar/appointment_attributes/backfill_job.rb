class Calendar::AppointmentAttributes::BackfillJob < ApplicationJob
  queue_as :low

  def perform(account_id)
    account = Account.find_by(id: account_id)
    return if account.nil? || Calendar::AppointmentAttributes::Definitions.enabled_keys(account).empty?

    contact_ids = account.calendar_events.where.not(contact_id: nil).select(:contact_id)
    account.contacts.where(id: contact_ids).select(:id).find_in_batches(batch_size: 100) do |contacts|
      contacts.each { |contact| Calendar::AppointmentAttributes::UpdateJob.perform_later(account_id, contact.id) }
    end
  end
end
