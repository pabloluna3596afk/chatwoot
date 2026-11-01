class Payphone::ExpirePendingPaymentsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    PayphonePayment.where(status: 'pending').where('created_at <= ?', 15.minutes.ago).find_each do |payment|
      payment.transition_to!('expired') if payment.pending?
    end
  end
end
