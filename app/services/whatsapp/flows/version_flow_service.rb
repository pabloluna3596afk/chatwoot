module Whatsapp
  module Flows
    class VersionFlowService
      GRAPH_VERSION = 'v22.0'
      GRAPH_HOST = 'https://graph.facebook.com'

      def initialize(flow, channel, old_publication)
        @flow = flow
        @channel = channel
        @old_publication = old_publication
        @waba_id = channel.provider_config['business_account_id']
        @access_token = channel.provider_config['access_token']
      end

      def perform
        validate_inputs!
        create_new_flow
        upload_new_flow_json
        publish_new_flow
        deprecate_old_flow
        update_publication_records
        { success: true, new_meta_flow_id: @new_publication.meta_flow_id, old_meta_flow_id: @old_publication.meta_flow_id }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      private

      def validate_inputs!
        raise 'Flow not found' if @flow.blank?
        raise 'Old publication not found' if @old_publication.blank?
        raise 'Old flow not published' unless @old_publication.published_in_meta?
      end

      def create_new_flow
        url = "#{GRAPH_HOST}/#{GRAPH_VERSION}/#{@waba_id}/flows"
        body = {
          name: @flow.name,
          categories: map_flow_categories,
          clone_flow_id: @old_publication.meta_flow_id
        }

        response = make_request(:post, url, body)
        @new_meta_flow_id = response['id']
      end

      def upload_new_flow_json
        url = "#{GRAPH_HOST}/#{GRAPH_VERSION}/#{@new_meta_flow_id}/assets"
        flow_json = @flow.flow_json.is_a?(String) ? JSON.parse(@flow.flow_json) : @flow.flow_json

        response = make_multipart_request(url, flow_json)

        @validation_errors = response['validation_errors'] if response['validation_errors'].present?
      end

      def publish_new_flow
        url = "#{GRAPH_HOST}/#{GRAPH_VERSION}/#{@new_meta_flow_id}/publish"

        response = make_request(:post, url, {})
        fetch_new_flow_status if response['success']
      end

      def fetch_new_flow_status
        url = "#{GRAPH_HOST}/#{GRAPH_VERSION}/#{@new_meta_flow_id}"
        response = make_request(:get, url, nil)

        @new_status = response['status'].downcase
        @validation_errors = response['validation_errors'] if response['validation_errors'].present?
      end

      def deprecate_old_flow
        url = "#{GRAPH_HOST}/#{GRAPH_VERSION}/#{@old_publication.meta_flow_id}/deprecate"

        response = make_request(:post, url, {})
        raise 'Failed to deprecate old flow' unless response['success']
      end

      def update_publication_records
        # Create or update new publication record
        @new_publication = WhatsappFlowPublication.find_or_create_by(
          whatsapp_flow_id: @flow.id,
          waba_id: @waba_id
        )
        @new_publication.meta_flow_id = @new_meta_flow_id
        @new_publication.status = @new_status || 'published'
        @new_publication.validation_errors = @validation_errors if @validation_errors.present?
        @new_publication.published_version = (@old_publication.published_version || 0) + 1
        @new_publication.old_meta_flow_id = @old_publication.meta_flow_id
        @new_publication.published_at = Time.current
        @new_publication.save!

        # Mark old publication as deprecated
        @old_publication.status = 'deprecated'
        @old_publication.save!
      end

      def map_flow_categories
        return [] if @flow.flow_categories.blank?

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
    end
  end
end
