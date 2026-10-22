import { mount } from '@vue/test-utils';
import CaptainResponderStatus from '../CaptainResponderStatus.vue';

const mountStatus = state =>
  mount(CaptainResponderStatus, {
    global: {
      mocks: {
        $t: (key, params) => `${key}${params ? JSON.stringify(params) : ''}`,
      },
      plugins: [
        {
          install(app) {
            app.config.globalProperties.$store = {};
          },
        },
      ],
      provide: {},
    },
    props: {},
    ...state,
  });

vi.mock('vuex', () => ({
  useStore: () => ({ getters: { getSelectedChat: {} } }),
}));
const mockState = vi.hoisted(() => ({ value: {} }));
vi.mock('dashboard/composables/useCaptainState', async () => {
  const { ref } = await import('vue');
  return {
    useCaptainState: () => ({
      isAiAttended: ref(Boolean(mockState.value.attended)),
      isEscalated: ref(Boolean(mockState.value.escalated)),
      assistant: ref({ name: 'Aurora' }),
      isWaitingForCustomer: ref(false),
    }),
  };
});

describe('CaptainResponderStatus', () => {
  it('says who answers, without repeating the Captain name next to its icon', () => {
    mockState.value = { attended: true };
    const wrapper = mountStatus();
    expect(wrapper.text()).toContain(
      'CONVERSATION_SIDEBAR.RESPONDER.ANSWERING'
    );
    expect(wrapper.text()).toContain('Aurora');
  });

  it('warns when the conversation was passed to the team', () => {
    mockState.value = { escalated: true };
    const wrapper = mountStatus();
    expect(wrapper.text()).toContain(
      'CONVERSATION_SIDEBAR.RESPONDER.ESCALATED'
    );
  });

  it('renders nothing when nobody has taken over', () => {
    mockState.value = {};
    expect(
      mountStatus().find('[data-testid="responder-status"]').exists()
    ).toBe(false);
  });
});
