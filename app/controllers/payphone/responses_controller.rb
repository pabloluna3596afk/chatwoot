class Payphone::ResponsesController < ApplicationController
  skip_before_action :authenticate_user!, :set_current_user, only: :show

  def show
    transaction_id = params[:id]
    client_transaction_id = params[:clientTransactionId]
    return head :bad_request unless transaction_id.to_s.match?(/\A\d{1,20}\z/) &&
                                    client_transaction_id.to_s.match?(/\A[0-9a-f-]{36}\z/i)

    payment = PayphonePayment.find_by(client_transaction_id: client_transaction_id)
    return head :not_found unless payment
    return head :unprocessable_entity if preview_fake?

    Payphone::ConfirmPayment.new(payment: payment, transaction_id: transaction_id,
                                 client_transaction_id: client_transaction_id).call
    redirect_to "/app/accounts/#{payment.account_id}/settings/billing?payphone=#{payment.status}", allow_other_host: false
  rescue Payphone::ConfirmationError
    redirect_to "/app/accounts/#{payment.account_id}/settings/billing?payphone=verifying", allow_other_host: false
  rescue Payphone::PaidPlanActive
    redirect_to "/app/accounts/#{payment.account_id}/settings/billing?payphone=conflict", allow_other_host: false
  rescue Payphone::IncongruentConfirmation
    redirect_to "/app/accounts/#{payment.account_id}/settings/billing?payphone=failed", allow_other_host: false
  end

  private

  def preview_fake?
    ENV['PAYPHONE_PREVIEW_FAKE'] == '1'
  end
end
