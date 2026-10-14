class Calendar::AppointmentAttributes::UpdateJob < ApplicationJob
  queue_as :low

  def perform(account_id, contact_id)
    contact = Contact.find_by(account_id: account_id, id: contact_id)
    Calendar::AppointmentAttributes::Updater.new(contact: contact).perform
  end
end
