require 'rails_helper'

RSpec.describe Whatsapp::HeaderMediaCleanupJob do
  it 'runs the cleanup on the purgable queue' do
    service = instance_double(Whatsapp::HeaderMediaCleanupService, perform: 0)
    allow(Whatsapp::HeaderMediaCleanupService).to receive(:new).and_return(service)

    described_class.perform_now

    expect(service).to have_received(:perform)
    expect(described_class.new.queue_name).to eq('purgable')
  end
end
