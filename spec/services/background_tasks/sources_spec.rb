require 'rails_helper'

RSpec.describe BackgroundTasks::Sources do
  let(:account) { build_stubbed(:account) }
  let(:user) { build_stubbed(:user) }

  it 'passes account and user to each registered source and keeps the shared payload' do
    first = class_double(Whatsapp::TemplateBackgroundTask)
    second = class_double(Whatsapp::TemplateBackgroundTask)
    stub_const('BackgroundTasks::Sources::CLASSES', [first, second])
    task = { id: 'import:42', kind: 'import', title: 'Contacts', status: 'running', detail: nil, link: nil }
    expect(first).to receive(:tasks).with(account, user).and_return([task])
    expect(second).to receive(:tasks).with(account, user).and_return([])
    expect(described_class.tasks(account, user)).to eq([task])
  end

  it 'bounds the combined response' do
    results = Array.new(25) { |id| { id: id, status: 'success', updated_at: id.to_s } }
    allow(Whatsapp::TemplateBackgroundTask).to receive(:tasks).with(account, user).and_return(results)
    expect(described_class.tasks(account, user).length).to eq(described_class::LIMIT)
  end

  it 'keeps all active tasks ahead of the last twenty results' do
    tasks = [{ id: 'active', status: 'running' }] + Array.new(21) { |id| { id: id, status: 'error', updated_at: id.to_s } }
    allow(Whatsapp::TemplateBackgroundTask).to receive(:tasks).with(account, user).and_return(tasks)
    result = described_class.tasks(account, user)
    expect(result.first[:id]).to eq('active')
    expect(result.length).to eq(21)
  end
end
