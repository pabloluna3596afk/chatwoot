#!/usr/bin/env ruby
# Real-API runner for PR 2: Flows to Meta (TEST WABA only)
# Usage: WHATSAPP_TEST_TOKEN=... rails runner script/flows_meta_test.rb

require 'net/http'
require 'json'

GRAPH_VERSION = 'v22.0'
GRAPH_HOST = 'https://graph.facebook.com'
TEST_WABA_ID = '1554207416398687'
TEST_PHONE = ENV['TEST_PHONE'] || '+551140414141'  # Default: test number placeholder

token = ENV['WHATSAPP_TEST_TOKEN']
raise 'Error: WHATSAPP_TEST_TOKEN environment variable not set' if token.blank?

puts "Starting real-API test flow (TEST WABA only)"
puts "=" * 60

# Step 1: Create flow
puts "\n[1/5] Creating flow in Meta..."
create_url = "#{GRAPH_HOST}/#{GRAPH_VERSION}/#{TEST_WABA_ID}/flows"
create_body = {
  name: "Test Flow #{Time.current.to_i}",
  categories: ['SIGN_UP']
}

create_response = make_request(:post, create_url, create_body, token)
flow_id = create_response['id']
puts "✓ Flow created: #{flow_id}"

# Step 2: Upload Flow JSON
puts "\n[2/5] Uploading Flow JSON asset..."
upload_url = "#{GRAPH_HOST}/#{GRAPH_VERSION}/#{flow_id}/assets"
test_flow_json = {
  version: '7.3',
  screens: [
    {
      id: 'screen_0',
      title: 'Welcome',
      layout: {
        type: 'SingleColumnLayout',
        children: [
          { type: 'Text', text: 'Test flow from API' }
        ]
      }
    }
  ]
}

upload_response = make_multipart_request(upload_url, test_flow_json, token)
puts "✓ Asset uploaded"
if upload_response['validation_errors'].present?
  puts "⚠ Validation errors:"
  upload_response['validation_errors'].each do |err|
    puts "  - #{err['error_description']}"
  end
end

# Step 3: Publish flow
puts "\n[3/5] Publishing flow..."
publish_url = "#{GRAPH_HOST}/#{GRAPH_VERSION}/#{flow_id}/publish"
publish_response = make_request(:post, publish_url, {}, token)
puts "✓ Flow published" if publish_response['success']

# Step 4: Send draft test message
puts "\n[4/5] Sending test message to #{TEST_PHONE}..."
messages_url = "#{GRAPH_HOST}/#{GRAPH_VERSION}/#{TEST_WABA_ID}/messages"
message_payload = {
  messaging_product: 'whatsapp',
  to: TEST_PHONE,
  type: 'interactive',
  interactive: {
    type: 'flow',
    action: {
      name: 'flow',
      parameters: {
        flow_message_version: '3',
        flow_id: flow_id,
        flow_cta: 'Abrir',
        mode: 'draft',
        flow_action: 'navigate',
        flow_action_payload: {
          screen: 'screen_0'
        }
      }
    }
  }
}

send_response = make_request(:post, messages_url, message_payload, token)
if send_response['messages']
  puts "✓ Test message sent: #{send_response['messages'].first['id']}"
else
  puts "✗ Failed to send test message"
  puts "  Error: #{send_response['error']&.dig('message') || send_response['error']}"
end

# Step 5: Delete flow (only drafts can be deleted)
puts "\n[5/5] Cleaning up: deleting test flow..."
delete_url = "#{GRAPH_HOST}/#{GRAPH_VERSION}/#{flow_id}"
begin
  delete_response = make_request(:delete, delete_url, nil, token)
  puts "✓ Test flow deleted" if delete_response['success']
rescue => e
  puts "⚠ Could not delete flow (may have been published)"
  puts "  Note: Published flows must be deprecated, not deleted"
end

puts "\n" + "=" * 60
puts "✓ Real-API test completed successfully"
puts "Token was never printed in output. Check logs if needed."

# Helper methods

def make_request(method, url, body, token)
  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = case method
            when :post
              Net::HTTP::Post.new(uri.request_uri)
            when :get
              Net::HTTP::Get.new(uri.request_uri)
            when :delete
              Net::HTTP::Delete.new(uri.request_uri)
            else
              raise "Unsupported method: #{method}"
            end

  request['Authorization'] = "Bearer #{token}"
  request['Content-Type'] = 'application/json'
  request.body = body.to_json if body.present?

  response = http.request(request)
  parse_response(response)
end

def make_multipart_request(url, flow_json, token)
  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = Net::HTTP::Post.new(uri.request_uri)
  request['Authorization'] = "Bearer #{token}"

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
