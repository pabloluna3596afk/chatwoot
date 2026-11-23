require 'rails_helper'

RSpec.describe Calendar::TemplateResources do
  self.use_transactional_tests = false
  include_context 'with an empty database after the example'

  let!(:account) { create(:account) }

  [nil, 'shared-waba'].each do |waba|
    it "serializes two preparations for WABA #{waba.inspect} into one identity" do
      channels = if waba
                   Array.new(2) do
                     channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                                         validate_provider_config: false)
                     channel.update!(provider_config: channel.provider_config.merge('business_account_id' => waba))
                     channel
                   end
                 else
                   [nil, nil]
                 end
      ready = Queue.new
      start = Queue.new
      threads = channels.map do |channel|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            start.pop
            described_class.new(account: Account.find(account.id), function: :confirmation, language: 'es', channel: channel).prepare!.id
          end
        end
      end
      Timeout.timeout(10) { 2.times { ready.pop } }
      2.times { start << true }
      ids = Timeout.timeout(10) { threads.map(&:value) }
      expect(ids.uniq.size).to eq(1)
      expect(account.calendar_template_resources.where(waba_id: waba).count).to eq(1)
    ensure
      threads&.each { |thread| thread.kill if thread.alive? }
    end
  end
end
