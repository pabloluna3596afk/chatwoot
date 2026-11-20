import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/conversation.json';
import CaptainGenerationDetails from '../CaptainGenerationDetails.vue';

const state = vi.hoisted(() => ({ session: null }));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    getters: {
      'captainAgentSessions/getSessionByMessageId': () => state.session,
      'captainAgentSessions/hasFetched': () => true,
      'captainAgentSessions/isFetching': () => false,
    },
  }),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: () => true }),
}));

vi.mock('../provider.js', async () => {
  const { ref } = await import('vue');
  return {
    useMessageContext: () => ({
      orientation: ref('left'),
      variant: ref('default'),
      createdAt: ref(1),
    }),
  };
});

describe('CaptainGenerationDetails safe session contract', () => {
  it.each([
    [{}, null],
    [{ creditsConsumed: { status: 'recorded', value: 0 } }, 'Credits: 0'],
    [
      {
        model: { status: 'recorded', value: 'test-model' },
        creditsConsumed: { status: 'recorded', value: 1 },
      },
      'Generated with test-model · Credits: 1',
    ],
    [{ creditsConsumed: { status: 'not_recorded' } }, null],
    [{ creditsConsumed: { status: 'not_applicable' } }, null],
  ])(
    'renders only recorded server-authorized technical values: %j',
    (technical, expected) => {
      state.session = {
        technical,
        summary: { actions: [{ type: 'tool', name: 'faq_lookup' }] },
        runContext: [
          { role: 'assistant', content: { reasoning: 'RAW SECRET' } },
        ],
        llmModel: 'LEGACY MODEL',
        creditsConsumed: 99,
      };
      const wrapper = mount(CaptainGenerationDetails, {
        props: { messageId: 7 },
        global: {
          plugins: [
            createI18n({ legacy: false, locale: 'en', messages: { en } }),
          ],
          directives: { tooltip: {} },
          stubs: {
            Icon: true,
            Popover: { template: '<div><slot name="content" /></div>' },
          },
        },
      });

      expect(wrapper.text()).toContain('FAQ Lookup');
      expect(wrapper.text()).not.toContain('RAW SECRET');
      expect(wrapper.text()).not.toContain('LEGACY MODEL');
      expect(wrapper.text()).not.toContain('99');
      if (expected) {
        expect(wrapper.text()).toContain(expected);
      } else {
        expect(wrapper.text()).not.toContain('Credits:');
        expect(wrapper.text()).not.toContain('Generated with');
      }
    }
  );
});
