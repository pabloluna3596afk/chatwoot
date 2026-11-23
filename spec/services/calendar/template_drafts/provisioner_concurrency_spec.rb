require 'rails_helper'

RSpec.describe Calendar::TemplateDrafts::Provisioner do
  self.use_transactional_tests = false
  include_context 'with an empty database after the example'

  let!(:account) { create(:account, locale: 'es') }

  it 'serializes simultaneous first connections without a WABA or duplicate drafts' do
    ready = Queue.new
    start = Queue.new
    threads = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          service = described_class.new(account: Account.find(account.id))
          ready << true
          start.pop
          service.perform
        end
      end
    end
    Timeout.timeout(10) { 2.times { ready.pop } }
    2.times { start << true }
    results = Timeout.timeout(10) { threads.map(&:value) }
    expect(results.first).to eq(results.last)
    expect(account.whatsapp_template_drafts.count).to eq(3)
    expect(account.calendar_template_resources.count).to eq(3)
    expect(account.reload.calendar_template_preparation['results'].values.pluck('status')).to eq(%w[created created created])
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
  end
end
