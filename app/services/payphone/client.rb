require 'net/http'

class Payphone::Client
  ENDPOINT = URI('https://paymentbox.payphonetodoesposible.com/api/confirm')

  def initialize(token: InstallationConfig.find_by(name: 'PAYPHONE_TOKEN')&.value)
    @token = token
  end

  def confirm(transaction_id:, client_transaction_id:)
    request = Net::HTTP::Post.new(ENDPOINT)
    request['Authorization'] = "Bearer #{@token}"
    request['Content-Type'] = 'application/json'
    request.body = { id: Integer(transaction_id), clientTxId: client_transaction_id }.to_json
    response = Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
      http.request(request)
    end
    raise Payphone::ConfirmationError unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue JSON::ParserError, ArgumentError, TypeError, Net::HTTPError, Net::OpenTimeout, Net::ReadTimeout,
         OpenSSL::SSL::SSLError, SocketError, IOError, SystemCallError
    raise Payphone::ConfirmationError
  end
end
