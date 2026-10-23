require 'rails_helper'

RSpec.describe AutomationRules::InternalTaskParameters do
  subject(:parameters) { described_class.new(params, account: account) }

  let(:account) { create(:account) }
  let(:params) { [{ 'title' => 'Call the customer' }] }

  it 'accepts only the required title' do
    expect(parameters.error).to be_nil
  end

  [nil, [], {}, 'task', [{ 'title' => 'Task' }, {}], [{ 'title' => nil }], [{ 'title' => 1 }],
   [{ 'title' => ' ' }], [{ 'title' => 'Task', 'unknown' => true }]].each do |value|
    context "with malformed parameters #{value.inspect}" do
      let(:params) { value }

      it 'names the action in the error' do
        expect(parameters.error).to include('create_internal_task')
      end
    end
  end

  [nil, [], {}, { 'duration' => '2', 'unit' => 'days' }, { 'duration' => 0, 'unit' => 'days' },
   { 'duration' => -1, 'unit' => 'hours' }, { 'duration' => 1.5, 'unit' => 'hours' },
   { 'duration' => 1, 'unit' => 'weeks' }, { 'duration' => 366, 'unit' => 'days' },
   { 'duration' => 8761, 'unit' => 'hours' }, { 'duration' => 525_601, 'unit' => 'minutes' },
   { 'duration' => 1, 'unit' => 'days', 'extra' => true }].each do |due_in|
    context "with invalid due_in #{due_in.inspect}" do
      let(:params) { [{ 'title' => 'Task', 'due_in' => due_in }] }

      it 'rejects the due date with an action-specific error' do
        expect(parameters.error).to include('create_internal_task', 'due_in')
      end
    end
  end

  [{ 'duration' => 365, 'unit' => 'days' }, { 'duration' => 8760, 'unit' => 'hours' },
   { 'duration' => 525_600, 'unit' => 'minutes' }].each do |due_in|
    context "with maximum due_in #{due_in.inspect}" do
      let(:params) { [{ 'title' => 'Task', 'due_in' => due_in }] }

      it 'accepts the shared 365-day limit' do
        expect(parameters.error).to be_nil
      end
    end
  end
end
