module Whatsapp
  module Flows
    class PublishToMetaService
      GRAPH_VERSION = 'v22.0'
      GRAPH_HOST = 'https://graph.facebook.com'
      META_FLOW_CATEGORIES = %w[SIGN_UP SIGN_IN APPOINTMENT_BOOKING LEAD_GENERATION CONTACT_US CUSTOMER_SUPPORT SURVEY OTHER].freeze

      def initialize(flow, channel)
        @flow = flow
        @channel = channel
        @waba_id = channel.provider_config['business_account_id']
        @access_token = channel.provider_config['access_token']
        @publication = nil
      end

      def perform
        validate_inputs!

        WhatsappFlowPublication.with_lock do
          ensure_publication_record
          ensure_flow_exists_in_meta
          upload_flow_json
          publish_flow
          record_status
        end

        { success: true, status: @publication.status, meta_flow_id: @publication.meta_flow_id, publication: @publication }
      rescue StandardError => e
        handle_error(e)
      end

      private

      def validate_inputs!
        raise 'Flow not found' if @flow.blank?
        raise 'Channel not found' if @channel.blank?
        raise 'WABA ID not found in channel config' if @waba_id.blank?
        raise 'Access token not found in channel config' if @access_token.blank?
      end

      def ensure_publication_record
        @publication = WhatsappFlowPublication.find_or_initialize_by(whatsapp_flow_id: @flow.id, waba_id: @waba_id)
        @publication.account_id = @channel.account_id
        @publication.status = 'draft' if @publication.new_record?
        @publication.save! if @publication.changed?
      end

      def ensure_flow_exists_in_meta
        return if @publication.meta_flow_id.present?

        response = create_flow_in_meta
        @publication.meta_flow_id = response['id']
        @publication.save!
      end

      def create_flow_in_meta
        url = "#{GRAPH_HOST}/#{GRAPH_VERSION}/#{@waba_id}/flows"
        body = {
          name: @flow.name,
          categories: map_flow_categories
        }

        response = make_request(:post, url, body)
        response
      end

      def upload_flow_json
        url = "#{GRAPH_HOST}/#{GRAPH_VERSION}/#{@publication.meta_flow_id}/assets"
        flow_json = @flow.flow_json.is_a?(String) ? JSON.parse(@flow.flow_json) : @flow.flow_json

        # Prepare multipart request
        response = make_multipart_request(url, flow_json)

        if response['validation_errors'].present?
          @publication.validation_errors = response['validation_errors']
          @publication.save!
        end

        response
      end

      def publish_flow
        url = "#{GRAPH_HOST}/#{GRAPH_VERSION}/#{@publication.meta_flow_id}/publish"

        begin
          response = make_request(:post, url, {})
          fetch_and_record_status if response['success']
        rescue StandardError => e
          @publication.status = 'draft'
          @publication.validation_errors = [{ error: e.message }]
          @publication.save!
          raise
        end
      end

      def fetch_and_record_status
        url = "#{GRAPH_HOST}/#{GRAPH_VERSION}/#{@publication.meta_flow_id}"
        response = make_request(:get, url, nil)

        @publication.status = response['status'].downcase
        @publication.validation_errors = response['validation_errors']
        @publication.published_at = Time.current
        @publication.save!
      end

      def record_status
        # Status already recorded in fetch_and_record_status
      end

      def map_flow_categories
        return [] if @flow.flow_categories.blank?

        # Map internal category names to Meta's categories
        category_map = {
          'sign_up' => 'SIGN_UP',
          'sign_in' => 'SIGN_IN',
          'appointment_booking' => 'APPOINTMENT_BOOKING',
          'lead_generation' => 'LEAD_GENERATION',
          'contact_us' => 'CONTACT_US',
          'customer_support' => 'CUSTOMER_SUPPORT',
          'survey' => 'SURVEY',
          'other' => 'OTHER'
        }

        @flow.flow_categories.map { |cat| category_map[cat.downcase] || 'OTHER' }.compact
      end

      def make_request(method, url, body)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = case method
                  when :post
                    Net::HTTP::Post.new(uri.request_uri)
                  when :get
                    Net::HTTP::Get.new(uri.request_uri)
                  else
                    raise "Unsupported method: #{method}"
                  end

        request['Authorization'] = "Bearer #{@access_token}"
        request['Content-Type'] = 'application/json'
        request.body = body.to_json if body.present?

        response = http.request(request)
        parse_response(response)
      end

      def make_multipart_request(url, flow_json)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri.request_uri)
        request['Authorization'] = "Bearer #{@access_token}"

        # Create multipart body
        boundary = "----WebKitFormBoundary#{SecureRandom.hex(8)}"
        request['Content-Type'] = "multipart/form-data; boundary=#{boundary}"

        body_parts = []
        body_parts << "--#{boundary}"
        body_parts << 'Content-Disposition: form-data; name="file"; filename="flow.json"'
        body_parts << 'Content-Type: application/json'
        body_parts << ''
        body_parts << flow_json.to_json
        body_parts << "--#{boundary}"
        body_parts << 'Content-Disposition: form-data; name="name"'
        body_parts << ''
        body_parts << 'flow.json'
        body_parts << "--#{boundary}"
        body_parts << 'Content-Disposition: form-data; name="asset_type"'
        body_parts << ''
        body_parts << 'FLOW_JSON'
        body_parts << "--#{boundary}--"

        request.body = body_parts.join("\r\n")

        response = http.request(request)
        parse_response(response)
      end

      def parse_response(response)
        case response.code.to_i
        when 200..299
          JSON.parse(response.body)
        when 400..599
          error_body = JSON.parse(response.body) rescue { 'error' => response.body }
          raise "Meta API error (#{response.code}): #{error_body}"
        else
          raise "Unexpected response code: #{response.code}"
        end
      end

      def handle_error(error)
        @publication.status = 'draft'
        @publication.validation_errors = [{ error: error.message }]
        @publication.save! if @publication.persisted?

        { success: false, error: error.message, publication: @publication }
      end
    end
  end
end
