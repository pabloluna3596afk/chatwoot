require 'rails_helper'

RSpec.describe Captain::Assistant do
  let(:account) { create(:account, locale: 'es') }
  let(:assistant) { create(:captain_assistant, account: account, name: 'Sofia', config: { 'product_name' => 'Shop' }) }
  let(:scenario) { create(:captain_scenario, account: account, assistant: assistant) }
  let(:missing_language_contexts) { [{}, { account_language: nil }] }

  it 'renders the business facts block only with filled fields' do
    expect(assistant.agent_instructions).not_to include('# Business facts')
    assistant.update!(config: assistant.config.merge('business_facts' => { 'hours' => " Monday\nFriday ", 'address' => '   ' }))

    prompt = assistant.agent_instructions
    expect(prompt).to include('# Business facts', '- Opening hours: Monday Friday')
    expect(prompt).not_to include('- Address:', '- Payment methods:', '- Delivery:', '- How to book or order:')

    assistant.update!(config: assistant.config.merge('business_facts' => { 'hours' => '' }))
    expect(assistant.agent_instructions).not_to include('# Business facts')
  end

  it 'renders the business facts for scenarios' do
    expect(scenario.agent_instructions).not_to include('# Business facts')
    assistant.update!(config: assistant.config.merge('business_facts' => Captain::BusinessFactsValidator::FIELDS.index_with { 'Saved fact' }))

    prompt = scenario.agent_instructions
    expect(prompt).to include('# Business facts', '- Opening hours: Saved fact', '- Address: Saved fact',
                              '- Payment methods: Saved fact', '- Delivery: Saved fact', '- How to book or order: Saved fact')
  end

  it 'renders the business identity' do
    expect(assistant.agent_instructions).to include('You are Sofia, a helpful, friendly and knowledgeable assistant of the business Shop.',
                                                    'Answer only about Shop, what it sells and how it works.')
    expect(assistant.agent_instructions(nil, prompt_template: 'copilot_reply_suggestion')).to include('assistant for the product Shop')
  end

  %w[assistant scenario copilot_reply_suggestion].each do |template|
    it "renders the default language rule for #{template}" do
      agent = template == 'scenario' ? scenario : assistant
      expect(agent.agent_instructions(nil, prompt_template: template)).to include("reply in #{account.locale_english_name}.")
      account.update!(locale: 'en')
      expect(agent.agent_instructions(nil, prompt_template: template)).to include('reply in english.')
    end

    it "never renders an empty default language for #{template}" do
      missing_language_contexts.each do |context|
        prompt = Captain::PromptRenderer.render(template, context)
        expect(prompt).not_to match(/reply in\s*\./)
      end
    end
  end

  it 'renders the customer identity in English before verification' do
    prompt = Captain::PromptRenderer.render('assistant', can_verify_email: true)
    expect(prompt).to include('# Email verification', 'Before using a tool that requires verification, confirm with the customer')
    expect(prompt).not_to include('Antes de usar', 'Verificación')
  end

  it 'renders the customer identity in English after verification' do
    prompt = Captain::PromptRenderer.render('scenario', can_verify_email: true, verified_email: 'person@example.com')
    expect(prompt).to include('The customer verified they can access person@example.com.',
                              'Use only identifiers that a tool returned in this conversation for that email.')
  end
end
