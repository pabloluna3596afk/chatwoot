require 'rails_helper'

RSpec.describe 'Captain core rules prompt' do # rubocop:disable RSpec/DescribeClass
  let(:rules) { Rails.root.join('enterprise/lib/captain/prompts/snippets/core_rules.liquid').read }

  it 'asks for short, non-repeating replies' do
    expect(rules).to include('one idea per message and at most two short sentences')
    expect(rules).to include('Never repeat yourself')
    expect(rules).to include('do not restate or paraphrase')
  end

  it 'still renders inside the assistant prompt' do
    prompt = Captain::PromptRenderer.render('assistant', { 'product_name' => 'Acme', 'description' => 'Ventas' }.with_indifferent_access)

    expect(prompt).to include('one idea per message')
  end

  it 'identifies human messages as already told to the customer in the assistant prompt' do
    prompt = Captain::PromptRenderer.render('assistant', { 'product_name' => 'Acme', 'description' => 'Sales' }.with_indifferent_access)

    expect(prompt).to include('Messages that start with `[Human agent]:` were written by a person from the team')
    expect(prompt).to include('never contradict it, never repeat it, and never claim you wrote it')
  end
end
