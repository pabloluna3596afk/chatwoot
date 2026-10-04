require 'rails_helper'

RSpec.describe 'Captain core rules prompt' do
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
end
