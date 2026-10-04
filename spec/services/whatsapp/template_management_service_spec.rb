require 'rails_helper'

RSpec.describe Whatsapp::TemplateManagementService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:service) { described_class.new(channel) }
  let(:waba) { channel.provider_config['business_account_id'] }
  let(:base) { "https://graph.facebook.com/#{described_class::API_VERSION}" }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:provider_service) { instance_double(Whatsapp::Providers::WhatsappCloudService, sync_templates: nil) }
  let(:components) { [{ type: 'BODY', text: 'Hola' }] }

  before do
    allow(channel).to receive(:provider_service).and_return(provider_service)
  end

  def meta_error(code:, message:, subcode: nil, user_msg: nil)
    error = { message: message, type: 'OAuthException', code: code, error_subcode: subcode, error_user_msg: user_msg }.compact
    { status: 400, headers: json, body: { error: error }.to_json }
  end

  def error_of
    yield
    nil
  rescue described_class::Error => e
    e
  end

  describe '#create' do
    it 'posts the template to the WABA with the channel token and refreshes the list' do
      stub = stub_request(:post, "#{base}/#{waba}/message_templates")
             .with(headers: { 'Authorization' => "Bearer #{channel.template_access_token}" },
                   body: { name: 'recordatorio', language: 'es', category: 'UTILITY', components: components }.to_json)
             .to_return(status: 200, body: { id: '999', status: 'PENDING', category: 'UTILITY' }.to_json,
                        headers: json)

      result = service.create(name: 'recordatorio', language: 'es', category: 'UTILITY', components: components)

      expect(result).to eq(id: '999', status: 'PENDING', category: 'UTILITY')
      expect(stub).to have_been_requested
      expect(provider_service).to have_received(:sync_templates)
    end

    it 'asks Meta for a named template when the form uses named variables' do
      stub = stub_request(:post, "#{base}/#{waba}/message_templates")
             .with(body: hash_including('parameter_format' => 'NAMED'))
             .to_return(status: 200, body: { id: '1', status: 'PENDING', category: 'UTILITY' }.to_json, headers: json)

      service.create(name: 'a', language: 'es', category: 'UTILITY', components: components, parameter_format: 'NAMED')

      expect(stub).to have_been_requested
    end

    it 'does not send parameter_format for numbered templates' do
      stub = stub_request(:post, "#{base}/#{waba}/message_templates")
             .with { |request| JSON.parse(request.body).exclude?('parameter_format') }
             .to_return(status: 200, body: { id: '1', status: 'PENDING', category: 'UTILITY' }.to_json, headers: json)

      service.create(name: 'a', language: 'es', category: 'UTILITY', components: components, parameter_format: 'POSITIONAL')

      expect(stub).to have_been_requested
    end

    it 'turns the Meta errors it knows into stable codes' do
      cases = {
        [2_388_024, 'x'] => 'name_exists',
        [100, 'Message template is being deleted, wait 30 days'] => 'name_locked',
        [100, 'You can only edit a template once in 24 hours'] => 'edit_limit',
        [100, 'You cannot change the category of an approved template'] => 'category_locked',
        [100, 'You reached the maximum number of message templates'] => 'template_limit',
        [190, 'Error validating access token'] => 'token_invalid',
        [4, 'Application request limit reached'] => 'rate_limited',
        [100, 'Invalid parameter'] => 'meta_error'
      }

      cases.each do |(code, message), expected|
        subcode = code > 1000 ? code : nil
        stub_request(:post, "#{base}/#{waba}/message_templates").to_return(meta_error(code: subcode ? 100 : code, subcode: subcode, message: message))

        error = error_of { service.create(name: 'a', language: 'es', category: 'UTILITY', components: components) }

        expect(error.code).to eq(expected), "#{message}: expected #{expected}, got #{error&.code}"
      end
    end

    it 'keeps what Meta says for the cases it does not know' do
      stub_request(:post, "#{base}/#{waba}/message_templates")
        .to_return(meta_error(code: 100, message: 'Invalid parameter', user_msg: 'El cuerpo tiene un formato no permitido'))

      error = error_of { service.create(name: 'a', language: 'es', category: 'UTILITY', components: components) }

      expect(error).to have_attributes(code: 'meta_error', detail: 'El cuerpo tiene un formato no permitido', meta_code: 100)
    end

    it 'reports a Meta that cannot be reached' do
      stub_request(:post, "#{base}/#{waba}/message_templates").to_timeout

      expect(error_of { service.create(name: 'a', language: 'es', category: 'UTILITY', components: components) }.code).to eq('meta_unreachable')
    end

    it 'does not refresh the list when Meta refuses' do
      stub_request(:post, "#{base}/#{waba}/message_templates").to_return(meta_error(code: 100, message: 'x'))

      error_of { service.create(name: 'a', language: 'es', category: 'UTILITY', components: components) }

      expect(provider_service).not_to have_received(:sync_templates)
    end
  end

  describe '#update' do
    it 'edits through the template id and sends the category only when given' do
      stub = stub_request(:post, "#{base}/555").with(body: { components: components }.to_json)
                                               .to_return(status: 200, body: { success: true }.to_json,
                                                          headers: json)

      expect(service.update('555', components: components)).to eq(id: '555', status: 'PENDING')
      expect(stub).to have_been_requested
      expect(provider_service).to have_received(:sync_templates)
    end

    it 'sends the category when it is given' do
      stub = stub_request(:post, "#{base}/555").with(body: { components: components, category: 'MARKETING' }.to_json)
                                               .to_return(status: 200, body: { success: true }.to_json,
                                                          headers: json)

      service.update('555', components: components, category: 'MARKETING')

      expect(stub).to have_been_requested
    end

    it 'raises the edit limit as a code' do
      stub_request(:post, "#{base}/555").to_return(meta_error(code: 100, message: 'Too many edits: 10 times in 30 days'))

      expect(error_of { service.update('555', components: components) }.code).to eq('edit_limit')
    end
  end

  describe '#delete' do
    it 'deletes by name and hsm_id so the other languages stay' do
      stub = stub_request(:delete, "#{base}/#{waba}/message_templates").with(query: { name: 'recordatorio', hsm_id: '555' })
                                                                       .to_return(status: 200, body: { success: true }.to_json,
                                                                                  headers: json)

      expect(service.delete(name: 'recordatorio', hsm_id: '555')).to eq(deleted: true)
      expect(stub).to have_been_requested
      expect(provider_service).to have_received(:sync_templates)
    end

    it 'deletes by name alone when there is no id' do
      stub = stub_request(:delete, "#{base}/#{waba}/message_templates").with(query: { name: 'recordatorio' })
                                                                       .to_return(status: 200, body: { success: true }.to_json,
                                                                                  headers: json)

      service.delete(name: 'recordatorio')

      expect(stub).to have_been_requested
    end

    it 'raises when Meta refuses' do
      stub_request(:delete, "#{base}/#{waba}/message_templates").with(query: hash_including(name: 'x'))
                                                                .to_return(meta_error(code: 132_001, message: 'Template name does not exist'))

      expect(error_of { service.delete(name: 'x') }.code).to eq('not_found')
    end
  end

  describe '#fetch' do
    it 'reads the live status with the rejection reason' do
      stub_request(:get, "#{base}/555").with(query: { fields: described_class::FIELDS })
                                       .to_return(status: 200, headers: json,
                                                  body: { id: '555', name: 'recordatorio', status: 'REJECTED', category: 'MARKETING',
                                                          language: 'es', rejected_reason: 'INVALID_FORMAT',
                                                          quality_score: { score: 'GREEN' }, components: components }.to_json)

      expect(service.fetch('555')).to include(id: '555', status: 'REJECTED', rejected_reason: 'INVALID_FORMAT', quality_score: 'GREEN')
    end
  end

  describe '#library' do
    it 'lists the Meta library with the filters and the next page' do
      stub = stub_request(:get, "#{base}/#{waba}/message_template_library")
             .with(query: { search: 'cita', language: 'es', limit: described_class::LIBRARY_PAGE })
             .to_return(status: 200, headers: json,
                        body: { data: [{ id: '1', name: 'appointment_reminder', language: 'es', category: 'UTILITY', body: 'Hola', extra: 'x' }],
                                paging: { cursors: { after: 'abc' } } }.to_json)

      result = service.library(search: 'cita', language: 'es')

      expect(stub).to have_been_requested
      expect(result[:next]).to eq('abc')
      expect(result[:templates]).to eq(
        [{ 'id' => '1', 'name' => 'appointment_reminder', 'language' => 'es', 'category' => 'UTILITY', 'body' => 'Hola' }]
      )
    end

    it 'raises what Meta refuses' do
      stub_request(:get, "#{base}/#{waba}/message_template_library").with(query: hash_including({}))
                                                                    .to_return(meta_error(code: 190, message: 'expired'))

      expect(error_of { service.library }.code).to eq('token_invalid')
    end
  end

  describe '#create_from_library' do
    it 'creates by the library name with the button inputs and refreshes the list' do
      inputs = [{ type: 'PHONE_NUMBER', phone_number: '+593999999999' }]
      stub = stub_request(:post, "#{base}/#{waba}/message_templates")
             .with(body: { name: 'recordatorio', language: 'es', category: 'UTILITY', library_template_name: 'appointment_reminder',
                           library_template_button_inputs: inputs }.to_json)
             .to_return(status: 200, headers: json, body: { id: '7', status: 'APPROVED', category: 'UTILITY' }.to_json)

      result = service.create_from_library(library_template_name: 'appointment_reminder', name: 'recordatorio', language: 'es',
                                           category: 'UTILITY', button_inputs: inputs)

      expect(result).to eq(id: '7', status: 'APPROVED', category: 'UTILITY')
      expect(stub).to have_been_requested
      expect(provider_service).to have_received(:sync_templates)
    end
  end
end
