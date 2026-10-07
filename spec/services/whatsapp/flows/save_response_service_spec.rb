require 'rails_helper'

RSpec.describe Whatsapp::Flows::SaveResponseService do
  let(:conversation) { create(:conversation) }
  let(:contact) { conversation.contact }
  let(:fields) do
    [
      { 'type' => 'short_text', 'key' => 'name', 'save_to' => { 'target' => 'contact.name' } },
      { 'type' => 'short_text', 'key' => 'email', 'save_to' => { 'target' => 'contact.email' } },
      { 'type' => 'short_text', 'key' => 'phone', 'save_to' => { 'target' => 'contact.phone' } },
      { 'type' => 'short_text', 'key' => 'document', 'save_to' => { 'target' => 'contact.document_number' } }
    ]
  end
  let(:outgoing) do
    create(:message, conversation: conversation, account: conversation.account, inbox: conversation.inbox, message_type: :outgoing,
                     additional_attributes: { 'whatsapp_flow' => { 'id' => 12, 'name' => 'Datos', 'fields' => fields } })
  end
  let(:incoming) { create(:message, conversation: conversation, account: conversation.account, inbox: conversation.inbox, message_type: :incoming) }
  let(:token) { Whatsapp::Flows::ResponseToken.generate(outgoing) }
  let(:payload) { { 'flow_token' => token, 'name' => 'Updated', 'email' => '', 'phone' => 'invalid', 'document' => '' } }

  it 'stores only display metadata from the validated snapshot and still saves contact fields' do
    response_fields = [
      { 'key' => 'name', 'label' => 'Nombre', 'type' => 'short_text' },
      { 'key' => 'interests', 'label' => 'Intereses', 'type' => 'checkbox', 'options' => [{ 'id' => 'news', 'title' => 'Novedades' }] }
    ]
    outgoing.update!(additional_attributes: { 'whatsapp_flow' => outgoing.additional_attributes.fetch('whatsapp_flow')
                                                                                   .merge('response_fields' => response_fields) })
    answers = payload.merge('interests' => ['news'])
    incoming.update!(content_attributes: { 'whatsapp_flow_response' => answers.except('flow_token') })
    described_class.new(incoming, answers).perform
    expect(incoming.reload.content_attributes.fetch('whatsapp_flow_meta')).to eq('name' => 'Datos', 'fields' => response_fields)
    expect(incoming.content_attributes.fetch('whatsapp_flow_response')).to eq(answers.except('flow_token'))
    expect(incoming.content_attributes.fetch('whatsapp_flow_meta').to_json).not_to include(token, 'save_to', 'flow_token')
    expect(contact.reload.name).to eq('Updated')
  end

  it 'supports outgoing snapshots created before display metadata was added' do
    described_class.new(incoming, payload).perform
    expect(incoming.reload.content_attributes.fetch('whatsapp_flow_meta')).to eq('name' => 'Datos', 'fields' => [])
    expect(contact.reload.name).to eq('Updated')
  end

  it 'stores metadata for a Flow without contact save targets' do
    response_fields = [{ 'key' => 'city', 'label' => 'Ciudad', 'type' => 'short_text' }]
    outgoing.update!(additional_attributes: { 'whatsapp_flow' => {
      'name' => 'Consulta', 'fields' => [], 'response_fields' => response_fields
    } })
    described_class.new(incoming, { 'flow_token' => token, 'city' => 'Quito' }).perform
    expect(incoming.reload.content_attributes.fetch('whatsapp_flow_meta')).to eq('name' => 'Consulta', 'fields' => response_fields)
    expect(contact.reload.name).not_to eq('Updated')
  end

  it 'saves valid answers, skips invalid/blank fields and notes exactly once' do
    2.times { described_class.new(incoming, payload).perform }
    expect(contact.reload.name).to eq('Updated')
    expect(contact.email).to be_present
    expect(conversation.messages.where(private: true).count).to eq(1)
    note = conversation.messages.find_by!(private: true).content
    expect(note).to include('Formulario completado: Datos', 'contact.name', 'contact.email', 'contact.phone')
    expect(note).not_to include(token)
  end

  it 'ignores unknown and tampered tokens' do
    ["#{token}x", 'unknown'].each { |value| described_class.new(incoming, payload.merge('flow_token' => value)).perform }
    expect(contact.reload.name).not_to eq('Updated')
    expect(conversation.messages.where(private: true)).to be_empty
    expect(incoming.reload.content_attributes['whatsapp_flow_meta']).to be_nil
  end

  it 'rejects other accounts and other sender identities' do
    foreign = create(:message)
    expect(Whatsapp::Flows::ResponseToken.resolve(token, foreign)).to be_nil
    other = create(:conversation, account: conversation.account, inbox: conversation.inbox)
    incoming.update!(conversation: other)
    expect(Whatsapp::Flows::ResponseToken.resolve(token, incoming)).to be_nil
  end

  it 'saves and notes on the original conversation after it was resolved' do
    conversation.resolved!
    reopened = create(:conversation, account: conversation.account, inbox: conversation.inbox, contact: contact,
                                     contact_inbox: conversation.contact_inbox)
    incoming.update!(conversation: reopened)
    described_class.new(incoming, payload).perform
    expect(conversation.messages.where(private: true).count).to eq(1)
    expect(reopened.messages.where(private: true)).to be_empty
  end

  it 'skips email, phone and document already used by another contact' do
    other = create(:contact, account: conversation.account, email: 'used@example.com', phone_number: '+593991234567', document_number: '123')
    described_class.new(incoming, payload.merge('email' => other.email, 'phone' => other.phone_number, 'document' => other.document_number)).perform
    expect(contact.reload.email).not_to eq(other.email)
    expect(contact.phone_number).not_to eq(other.phone_number)
    expect(contact.document_number).not_to eq(other.document_number)
    expect(conversation.messages.find_by!(private: true).content).to include('used by another contact')
  end

  it 'skips invalid email and phone without dropping other answers' do
    described_class.new(incoming, payload.merge('email' => 'not-an-email', 'phone' => '123')).perform
    expect(contact.reload.name).to eq('Updated')
    expect(contact.email).not_to eq('not-an-email')
    expect(contact.phone_number).not_to eq('123')
    expect(conversation.messages.find_by!(private: true).content).to include('invalid value')
  end

  it 'preserves custom attributes, saves false and converts multiple checkbox answers to text' do
    create(:custom_attribute_definition, account: conversation.account, attribute_model: :contact_attribute,
                                         attribute_display_type: :checkbox, attribute_key: 'accept')
    create(:custom_attribute_definition, account: conversation.account, attribute_model: :contact_attribute,
                                         attribute_display_type: :text, attribute_key: 'choices')
    fields << { 'type' => 'optin', 'key' => 'accept', 'save_to' => { 'target' => 'contact.custom_attribute.accept' } }
    fields << { 'type' => 'checkbox', 'key' => 'choices', 'options' => [{ 'id' => 'a' }, { 'id' => 'b' }],
                'save_to' => { 'target' => 'contact.custom_attribute.choices' } }
    contact.update!(custom_attributes: { 'existing' => 'keep' })
    described_class.new(incoming, payload.merge('accept' => false, 'choices' => %w[a b])).perform
    expect(contact.reload.custom_attributes).to include('existing' => 'keep', 'accept' => false, 'choices' => 'a, b')
  end
end
