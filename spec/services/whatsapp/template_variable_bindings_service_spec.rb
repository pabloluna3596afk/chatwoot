require 'rails_helper'

RSpec.describe Whatsapp::TemplateVariableBindingsService do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:service) { described_class.new(channel) }
  let(:texts) { ['Hola {{nombre}}', 'Tu pedido {{pedido}} y {{ cupon }}'] }

  describe '#normalize' do
    it 'keeps the choices of the variables the template has' do
      clean = service.normalize({ pedido: 'contact.custom_attribute.pedido', cupon: 'conversation.custom_attribute.cupon' }, texts)

      expect(clean).to eq('pedido' => 'contact.custom_attribute.pedido', 'cupon' => 'conversation.custom_attribute.cupon')
    end

    it 'accepts the values of the shared table' do
      expect(service.normalize({ nombre: 'contact.first_name' }, texts)).to eq('nombre' => 'contact.first_name')
    end

    it 'is empty without choices' do
      expect(service.normalize(nil, texts)).to eq({})
      expect(service.normalize({}, texts)).to eq({})
    end

    it 'rejects a variable the template does not have' do
      expect { service.normalize({ otro: 'contact.name' }, texts) }.to raise_error(described_class::Invalid, /otro is not in the template/)
    end

    it 'rejects values that are not a known path' do
      ['sistema.secret', 'contact.name; drop', '{{ contact.name }}', 'contact', "contact.#{'a' * 130}"].each do |key|
        expect { service.normalize({ pedido: key }, texts) }.to raise_error(described_class::Invalid, /pedido has an invalid value/)
      end
    end

    it 'accepts exact catalog paths for Unicode, hyphens and dots without accepting arbitrary Liquid' do
      keys = %w[nivel-vip nivel.vip categoría]
      keys.each do |key|
        create(:custom_attribute_definition, account: channel.account, attribute_key: key, attribute_model: 'contact_attribute')
      end
      keys.map do |key|
        path = "contact.custom_attribute['#{key}']"
        expect(service.normalize({ pedido: path }, texts)).to eq('pedido' => path)
      end
      ["contact.custom_attribute['unknown']", "contact.custom_attribute['nivel-vip'] | upcase"].each do |path|
        expect { service.normalize({ pedido: path }, texts) }.to raise_error(described_class::Invalid)
      end
    end

    it 'rejects a list' do
      expect { service.normalize(['contact.name'], texts) }.to raise_error(described_class::Invalid)
    end
  end

  describe '#store, #for_template and #merge_into' do
    let(:templates) { [{ 'name' => 'pedido_listo', 'language' => 'es' }, { 'name' => 'sin_variables', 'language' => 'es' }, 'raro'] }

    it 'stores by template name, shares it between languages and adds it to the templates' do
      service.store('pedido_listo', 'pedido' => 'contact.custom_attribute.pedido')
      templates << { 'name' => 'pedido_listo', 'language' => 'en' }

      merged = service.merge_into(templates)

      expect(merged[0]).to include('variable_bindings' => { 'pedido' => 'contact.custom_attribute.pedido' })
      expect(merged[1]).to eq('name' => 'sin_variables', 'language' => 'es')
      expect(merged[2]).to eq('raro')
      expect(merged[3]).to include('variable_bindings' => { 'pedido' => 'contact.custom_attribute.pedido' })
    end

    it 'replaces the choices of a template and removes them when empty, leaving the others alone' do
      service.store('pedido_listo', 'pedido' => 'contact.name')
      service.store('otra', 'x' => 'contact.email')
      service.store('pedido_listo', 'pedido' => 'contact.city')
      expect(service.for_template('pedido_listo')).to eq('pedido' => 'contact.city')

      service.store('pedido_listo', {})
      expect(service.for_template('pedido_listo')).to eq({})
      expect(service.for_template('otra')).to eq('x' => 'contact.email')
    end

    it 'survives a template sync from Meta' do
      service.store('pedido_listo', 'pedido' => 'contact.name')
      channel.update_columns(message_templates: [{ 'name' => 'pedido_listo' }], message_templates_last_updated: Time.current) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.new(channel.reload).for_template('pedido_listo')).to eq('pedido' => 'contact.name')
    end
  end
end
