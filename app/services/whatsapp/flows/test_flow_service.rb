module Whatsapp
  module Flows
    class TestFlowService
      GRAPH_VERSION = 'v22.0'
      GRAPH_HOST = 'https://graph.facebook.com'

      def initialize(flow, channel, phone_number)
        @flow = flow
        @channel = channel
        @phone_number = phone_number
        @publication = WhatsappFlowPublication.find_by(whatsapp_flow_id: flow.id, waba_id: channel.provider_config['business_account_id'])
        @access_token = channel.provider_config['access_token']
      end

      def perform
        validate_inputs!
        ensure_flow_draft_in_meta
        send_test_flow
      rescue StandardError => e
        { success: false, error: e.message }
      end

      private

      def validate_inputs!
        raise 'Flow not found' if @flow.blank?
        raise 'Channel not found' if @channel.blank?
        raise 'Phone number required' if @phone_number.blank?
        raise 'Access token not found' if @access_token.blank?
      end

      def ensure_flow_draft_in_meta
        return if @publication&.meta_flow_id.present?

        # If flow doesn't have a publication record yet, create one in draft
        @publication ||= WhatsappFlowPublication.create!(
          whatsapp_flow_id: @flow.id,
          account_id: @channel.account_id,
          waba_id: @channel.provider_config['business_account_id'],
          status: 'draft'
        )

        # Create flow in Meta if not already present
        unless @publication.meta_flow_id.present?
          service = PublishToMetaService.new(@flow, @channel)
          service.perform
          @publication.reload
        end
      end

      def send_test_flow
        first_screen_id = extract_first_screen_id
        url = "#{GRAPH_HOST}/#{GRAPH_VERSION}/#{@channel.provider_config['business_account_id']}/messages"

        payload = {
          messaging_product: 'whatsapp',
          to: @phone_number,
          type: 'interactive',
          interactive: {
            type: 'flow',
            action: {
              name: 'flow',
              parameters: {
                flow_message_version: '3',
                flow_id: @publication.meta_flow_id,
                flow_cta: 'Abrir',
                mode: 'draft',
                flow_action: 'navigate',
                flow_action_payload: {
                  screen: first_screen_id
                }
              }
            }
          }
        }

        response = make_request(url, payload)

        if response['messages']
          { success: true, message_id: response['messages'].first['id'] }
        else
          { success: false, error: response['error']&.dig('message') || 'Failed to send test flow' }
        end
      end

      def extract_first_screen_id
        flow_json = @flow.flow_json.is_a?(String) ? JSON.parse(@flow.flow_json) : @flow.flow_json
        flow_json['screens']&.first&.dig('id') || 'screen_0'
      end

      def make_request(url, payload)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri.request_uri)
        request['Authorization'] = "Bearer #{@access_token}"
        request['Content-Type'] = 'application/json'
        request.body = payload.to_json

        response = http.request(request)
        parse_response(response)
      end

      def parse_response(response)
        case response.code.to_i
        when 200..299
          JSON.parse(response.body)
        when 400..599
          error_body = JSON.parse(response.body) rescue { 'error' => { 'message' => response.body } }
          raise "Meta API error (#{response.code}): #{error_body['error']&.dig('message') || error_body}"
        else
          raise "Unexpected response code: #{response.code}"
        end
      end
    end
  end
end
