require 'rails_helper'

RSpec.describe Captain::Capabilities do
  let(:registry) { YAML.load_file(Rails.root.join('config/agents/capabilities.yml')) }
  let(:allowed_kinds) { %w[template in_window in_window_or_template] }
  let(:allowed_scopes) { %w[assistant inbox] }
  let(:allowed_groups) { %w[whatsapp calendar none] }
  let(:allowed_roles) { %w[administrator] }
  let(:text_keys) { %w[TITLE DESCRIPTION] }
  let(:routes) do
    %w[
      app/javascript/dashboard/routes/dashboard/captain/captain.routes.js
      app/javascript/dashboard/routes/dashboard/settings/integrations/integrations.routes.js
    ].map { |path| File.read(Rails.root.join(path)) }.join("\n")
  end

  it 'declares unique capability and group identifiers' do
    capabilities = registry.fetch('capabilities')
    groups = registry.fetch('groups')
    expect(capabilities.map { |item| item.fetch('id') }.uniq).to eq(capabilities.map { |item| item.fetch('id') })
    expect(groups.map { |group| group.fetch('id') }.uniq).to eq(groups.map { |group| group.fetch('id') })
  end

  it 'has required fields, allowed values and loadable state classes' do
    capabilities = registry.fetch('capabilities')
    required_fields = %w[id group position kind scope configure_route status]
    capabilities.each do |item|
      expect(item.keys).to include(*required_fields)
      expect(allowed_kinds).to include(item.fetch('kind'))
      expect(allowed_scopes).to include(item.fetch('scope'))
      expect(allowed_groups).to include(item.fetch('group'))
      expect(allowed_roles).to include(item.fetch('manage_role', 'administrator'))
      expect(item.fetch('status').constantize.ancestors).to include(Captain::Capabilities::Base)
    end
  end

  it 'has translated title, description and reason copy' do
    locales = %w[es en].index_with do |locale|
      JSON.parse(File.read(Rails.root.join("app/javascript/dashboard/i18n/locale/#{locale}/integrations.json"))).dig(
        'CAPTAIN', 'ASSISTANTS', 'CAPABILITIES'
      )
    end
    registry.fetch('capabilities').each do |item|
      text_keys.each do |key|
        locales.each_value { |copy| expect(copy.dig('ITEMS', item.fetch('id'), key)).to be_present }
      end
    end
    Captain::Capabilities::Base::REASONS.each do |reason|
      locales.each_value { |copy| expect(copy.dig('REASONS', reason)).to be_present }
    end
  end

  it 'references routes that exist in the Captain and Integrations routers' do
    registry.fetch('capabilities').each do |item|
      expect(routes).to include("name: '#{item.fetch('configure_route')}'")
    end
    registry.fetch('groups').each do |group|
      expect(allowed_groups).to include(group.fetch('id'))
      next unless group['connect_route']

      expect(routes).to include("name: '#{group.fetch('connect_route')}'")
    end
  end
end
