import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import en from 'dashboard/i18n/locale/en/conversation.json';
import es from 'dashboard/i18n/locale/es/conversation.json';
import module from 'dashboard/store/captain/decisions';
import API from 'dashboard/api/captain/decisions';
import CaptainGenerationDetails from '../CaptainGenerationDetails.vue';
import CaptainDecisionContent from '../CaptainDecisionContent.vue';

vi.mock('dashboard/api/captain/decisions', () => ({
  default: { getForMessage: vi.fn() },
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '2' } }),
}));
vi.mock('../provider.js', () => ({
  useMessageContext: () => ({
    conversationId: ref(42),
    orientation: ref('right'),
  }),
}));

const decision = {
  id: 3,
  kind: 'reply',
  outcome: 'created',
  origin: 'model',
  trigger: 'customer_message',
  reasonText: 'Used the opening hours FAQ.',
  evidence: {
    tools: ['faq_lookup'],
    sources: { faqs: [{ id: 4, title: 'Opening hours', usage: 'used' }] },
  },
  afterwards: { status: 'not_recorded', facts: [] },
  technical: {},
  canChangeSetting: false,
};
const global = () => ({
  plugins: [createI18n({ legacy: false, locale: 'en', messages: { en, es } })],
  stubs: {
    RouterLink: { props: ['to'], template: '<a :href="to"><slot /></a>' },
  },
});
const content = (entry = { loading: false, decisions: [decision] }) =>
  mount(CaptainDecisionContent, { props: { entry }, global: global() });

describe('Captain decision content', () => {
  it.each([
    [undefined, 'Loading details…'],
    [{ loading: true }, 'Loading details…'],
    [{ error: 'network' }, "We couldn't load the details."],
    [{ error: 'forbidden' }, "You don't have access to these details."],
    [{ decisions: [] }, 'No details are available for this message.'],
  ])('distinguishes state %j', (entry, text) => {
    const wrapper = mount(CaptainDecisionContent, {
      props: { entry },
      global: global(),
    });
    expect(wrapper.text()).toContain(text);
    expect(wrapper.find('footer').exists()).toBe(false);
  });

  it('retries a failed request and never offers retry for forbidden access', async () => {
    const wrapper = content({ error: 'network' });
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Retry')
      .trigger('click');
    expect(wrapper.emitted('retry')).toHaveLength(1);
    await wrapper.setProps({ entry: { error: 'forbidden' } });
    expect(wrapper.text()).not.toContain('Retry');
  });

  it.each([
    ['agent', {}, []],
    [
      'administrator',
      { creditsConsumed: { status: 'recorded', value: 0 } },
      ['Credits deducted: 0'],
    ],
    [
      'superadmin',
      {
        model: { status: 'not_recorded' },
        creditsConsumed: { status: 'recorded', value: 0 },
        cost: { status: 'not_applicable' },
      },
      ['Model: Not recorded', 'Credits deducted: 0', 'Cost: Not applicable'],
    ],
  ])(
    'renders the %s server-authorized fields',
    (_role, technical, expected) => {
      const wrapper = content({
        decisions: [
          {
            ...decision,
            technical,
            llmModel: 'FORBIDDEN LEGACY',
            creditsConsumed: 99,
            runContext: 'RAW SECRET',
          },
        ],
      });
      expected.forEach(text => expect(wrapper.text()).toContain(text));
      expect(wrapper.find('footer').exists()).toBe(expected.length > 0);
      expect(wrapper.text()).not.toMatch(/FORBIDDEN LEGACY|RAW SECRET|99/);
    }
  );

  it('uses only the authorized setting destination and closes on navigation', async () => {
    const wrapper = content();
    expect(wrapper.find('a[href*="settings"]').exists()).toBe(false);
    await wrapper.setProps({
      entry: {
        decisions: [
          {
            ...decision,
            canChangeSetting: true,
            settingDestination: '/app/accounts/2/captain/1/settings',
          },
        ],
      },
    });
    await wrapper.get('a').trigger('click');
    expect(wrapper.get('a').attributes('href')).toBe(
      '/app/accounts/2/captain/1/settings'
    );
    expect(wrapper.emitted('close')).toHaveLength(1);
  });

  it('keeps content order and separates consulted sources from sources used', () => {
    const wrapper = content({
      decisions: [
        {
          ...decision,
          evidence: {
            ...decision.evidence,
            sources: {
              faqs: decision.evidence.sources.faqs,
              documents: [
                { id: 5, title: 'Other document', usage: 'consulted' },
              ],
            },
          },
        },
      ],
    });
    expect(wrapper.findAll('h3').map(node => node.text())).toEqual([
      'Why',
      'Evidence',
      'Sources used',
      'Sources consulted',
      'Actions',
      'What happened next',
    ]);
    expect(wrapper.text()).not.toMatch(/Last customer message|View message/);
    expect(wrapper.find('time').exists()).toBe(false);
  });

  it('uses a state pill and keeps origin and rule values in a key-value grid', () => {
    const wrapper = content({
      decisions: [
        {
          ...decision,
          outcome: 'confirmed',
          evidence: { settings: { inactivityThresholdMinutes: 30 } },
        },
      ],
    });
    expect(wrapper.find('.bg-n-teal-3').exists()).toBe(true);
    expect(wrapper.findAll('dl dt').map(node => node.text())).toEqual([
      'Origin',
      'Rule',
    ]);
    expect(wrapper.findAll('dl dd').map(node => node.text())).toEqual([
      'Model',
      'Inactivity threshold: 30 minutes',
    ]);
    expect(wrapper.findAll('li').map(node => node.text())).not.toContain(
      'Inactivity threshold: 30 minutes'
    );
  });

  it('uses compact spacing and plain text for the reason and origin details', () => {
    const wrapper = content({
      decisions: [
        {
          ...decision,
          evidence: { settings: { inactivityThresholdMinutes: 30 } },
        },
      ],
    });
    const panel = wrapper.get('[role="dialog"]');
    expect(panel.classes()).toContain('md:w-96');
    expect(panel.classes()).toContain('leading-[1.4]');
    expect(wrapper.get('article').classes()).toContain('gap-2');
    expect(wrapper.get('article p').classes()).not.toContain('rounded-lg');
    expect(wrapper.get('dl').classes()).not.toContain('bg-n-solid-2');
  });

  it('shows the silence notice without claiming resolution or evaluation cost', () => {
    const wrapper = content({
      decisions: [{ ...decision, kind: 'close_unanswered', origin: 'time' }],
    });
    expect(wrapper.text()).toContain(
      en.CONVERSATION.CAPTAIN_DECISION.SILENCE_WARNING
    );
    expect(wrapper.text()).not.toContain(
      en.CONVERSATION.CAPTAIN_DECISION.EVALUATION_COST_NOTICE
    );
  });

  it('shows evaluation cost only for model evaluations', () => {
    const wrapper = content({
      decisions: [
        {
          ...decision,
          kind: 'completion_review',
          trigger: 'completion_signal',
        },
      ],
    });
    expect(wrapper.text()).toContain(
      en.CONVERSATION.CAPTAIN_DECISION.EVALUATION_COST_NOTICE
    );
  });
});

describe('Captain decision request path', () => {
  it('fetches only on opening, uses the message endpoint and updates expanded state', async () => {
    API.getForMessage.mockResolvedValue({
      data: [{ ...decision, reason_text: 'Server reason' }],
    });
    const store = createStore({
      modules: { captainDecisions: { ...module, state: { entries: {} } } },
    });
    const options = global();
    options.plugins.push(store);
    options.stubs.Popover = {
      emits: ['show', 'hide'],
      setup() {
        return { open: ref(false) };
      },
      template:
        '<div><div @click="open = !open; $emit(open ? \'show\' : \'hide\')"><slot /></div><slot v-if="open" name="content" :hide="() => { open = false; $emit(\'hide\'); }" /></div>',
    };
    const wrapper = mount(CaptainGenerationDetails, {
      props: { messageId: 7 },
      global: options,
    });
    expect(API.getForMessage).not.toHaveBeenCalled();
    const trigger = wrapper.get('button');
    expect(trigger.attributes('aria-expanded')).toBe('false');
    expect(trigger.classes()).toContain('size-6');
    await trigger.trigger('click');
    await flushPromises();
    expect(API.getForMessage).toHaveBeenCalledWith(42, 7);
    expect(trigger.attributes('aria-expanded')).toBe('true');
    expect(
      wrapper.get(`#${trigger.attributes('aria-controls')}`).attributes('role')
    ).toBe('dialog');
    expect(wrapper.text()).toContain('Server reason');
    await wrapper.get('button[aria-label="Close"]').trigger('click');
    expect(trigger.attributes('aria-expanded')).toBe('false');
  });
});
