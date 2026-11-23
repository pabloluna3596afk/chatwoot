require 'rails_helper'

RSpec.describe Calendar::TemplateDrafts::Linker do
  self.use_transactional_tests = false
  include_context 'with an empty database after the example'

  let!(:account) { create(:account, locale: 'es') }

  it 'serializes simultaneous links from two numbers of the same WABA into one unchanged version' do
    template = { 'id' => 'remote', 'name' => 'selected', 'language' => 'es', 'category' => 'UTILITY', 'status' => 'APPROVED',
                 'parameter_format' => 'NAMED', 'components' => [
                   { 'type' => 'BODY', 'text' => 'Hola {{nombre}}, cita {{cita}} el {{fecha}} a las {{hora}}.' },
                   { 'type' => 'BUTTONS', 'buttons' => %w[Confirmar Reagendar Cancelar].map { |text| { 'type' => 'QUICK_REPLY', 'text' => text } } }
                 ] }
    channels = Array.new(2) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                validate_provider_config: false, message_templates: [template])
    end
    ready = Queue.new
    start = Queue.new
    threads = channels.map do |channel|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          linker = described_class.new(account: Account.find(account.id), function: 'confirmation', channel_id: channel.id)
          ready << true
          start.pop
          linker.perform(template_name: 'selected', remote_template_id: 'remote')
        end
      end
    end
    Timeout.timeout(10) { 2.times { ready.pop } }
    2.times { start << true }
    results = Timeout.timeout(10) { threads.map(&:value) }
    expect(account.calendar_template_resources.count).to eq(1)
    expect(account.calendar_template_resources.sole).to have_attributes(status: 'linked', remote_template_id: 'remote')
    expect(results.first).to eq(results.last)
    expect(results.first['results']['confirmation']).to include('ready_destinations' => 1, 'total_destinations' => 1)
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
  end
end
