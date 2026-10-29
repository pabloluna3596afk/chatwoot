class Payphone::FakeClient
  def initialize(payment:, status_code:)
    @payment = payment
    @status_code = status_code
  end

  def confirm(transaction_id:, client_transaction_id:)
    raise Payphone::ConfirmationError if @status_code == 1

    {
      'statusCode' => @status_code,
      'status' => @status_code == 3 ? 'Approved' : 'Canceled',
      'transactionId' => transaction_id,
      'clientTransactionId' => client_transaction_id,
      'authorizationCode' => @status_code == 3 ? 'PREVIEW' : nil,
      'amount' => @payment.amount,
      'currency' => @payment.currency
    }.compact
  end
end
