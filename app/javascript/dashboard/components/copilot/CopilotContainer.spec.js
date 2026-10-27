import { nextTick, ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import CopilotActionItemsAPI from 'dashboard/api/captain/copilotActionItems';
import CopilotContainer from './CopilotContainer.vue';

const testState = vi.hoisted(() => ({
  dispatch: vi.fn(),
  refs: {},
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/captain/copilotActionItems', () => ({
  default: { get: vi.fn().mockResolvedValue({ data: [] }) },
}));
vi.mock('dashboard/composables/useConfig', () => ({
  useConfig: () => ({ isEnterprise: true }),
}));
vi.mock('dashboard/composables/useUISettings', async () => {
  const { ref: createRef } = await import('vue');
  return {
    useUISettings: () => ({
      uiSettings: createRef({ is_copilot_panel_open: true }),
      updateUISettings: vi.fn(),
    }),
  };
});
vi.mock('@vueuse/core', () => ({
  useWindowSize: () => ({ width: ref(1024) }),
}));
vi.mock('dashboard/composables/store', async () => {
  const { ref: createRef } = await import('vue');
  const refs = {
    getCurrentUser: createRef({ id: 1 }),
    'captainAssistants/getRecords': createRef([{ id: 7 }]),
    'captainAssistants/getUIFlags': createRef({ fetchingList: false }),
    getCopilotAssistant: createRef(null),
    getSelectedChat: createRef({ id: 1 }),
    getLastEmailInSelectedChat: createRef({ message_type: 0 }),
    getCurrentAccountId: createRef(1),
    'accounts/isFeatureEnabledonAccount': createRef(() => true),
  };
  testState.refs = refs;

  return {
    useMapGetter: key => refs[key],
    useStore: () => ({
      dispatch: testState.dispatch,
      getters: {
        'copilotMessages/getMessagesByThreadId': threadId =>
          threadId ? [{ id: threadId }] : [],
      },
    }),
  };
});

const mountComponent = () =>
  shallowMount(CopilotContainer, {
    global: {
      directives: { onClickOutside: {} },
      stubs: {
        Transition: { template: '<div><slot /></div>' },
        Copilot: {
          name: 'Copilot',
          props: ['messages', 'onSendMessage'],
          template: '<div />',
        },
      },
    },
  });

describe('CopilotContainer', () => {
  beforeEach(() => {
    testState.dispatch.mockReset();
    testState.dispatch.mockResolvedValue(undefined);
    testState.refs.getSelectedChat.value = { id: 1 };
  });

  it('keeps the selected thread when the conversation changes', async () => {
    testState.dispatch.mockImplementation(action =>
      action === 'copilotThreads/create'
        ? Promise.resolve({ id: 99 })
        : Promise.resolve()
    );
    const wrapper = mountComponent();
    const copilot = wrapper.findComponent({ name: 'Copilot' });

    const result = await copilot.props('onSendMessage')('Draft a reply');

    expect(result).toBe(true);
    expect(copilot.props('messages')).toEqual([{ id: 99 }]);

    testState.refs.getSelectedChat.value = { id: 2 };
    await nextTick();

    expect(copilot.props('messages')).toEqual([{ id: 99 }]);
  });

  it('keeps the floating panel available with or without a selected conversation', async () => {
    const wrapper = mountComponent();

    expect(wrapper.find('.fixed.z-40').exists()).toBe(true);

    testState.refs.getSelectedChat.value = null;
    await nextTick();

    expect(wrapper.find('.fixed.z-40').exists()).toBe(true);
  });

  it('retains a thread created while the selected conversation changes', async () => {
    let resolveRequest;
    testState.dispatch.mockImplementation(action => {
      if (action !== 'copilotThreads/create') return Promise.resolve();
      return new Promise(resolve => {
        resolveRequest = resolve;
      });
    });
    const wrapper = mountComponent();
    const copilot = wrapper.findComponent({ name: 'Copilot' });

    const sendPromise = copilot.props('onSendMessage')('Draft a reply');
    await nextTick();
    testState.refs.getSelectedChat.value = { id: 2 };
    await nextTick();
    resolveRequest({ id: 99 });

    expect(await sendPromise).toBe(true);

    expect(copilot.props('messages')).toEqual([{ id: 99 }]);
  });

  it('keeps a successful send when loading action items fails', async () => {
    testState.dispatch.mockImplementation(action =>
      action === 'copilotThreads/create'
        ? Promise.resolve({ id: 99 })
        : Promise.resolve()
    );
    vi.mocked(CopilotActionItemsAPI.get).mockRejectedValueOnce(
      new Error('Could not load action items')
    );
    const wrapper = mountComponent();
    const copilot = wrapper.findComponent({ name: 'Copilot' });

    const result = await copilot.props('onSendMessage')('Draft a reply');

    expect(result).toBe(true);
    expect(copilot.props('messages')).toEqual([{ id: 99 }]);
  });

  it('reports a failed send', async () => {
    testState.dispatch.mockImplementation(action =>
      action === 'copilotThreads/create'
        ? Promise.reject(new Error('Could not send'))
        : Promise.resolve()
    );
    const wrapper = mountComponent();
    const copilot = wrapper.findComponent({ name: 'Copilot' });

    const result = await copilot.props('onSendMessage')('Draft a reply');

    expect(result).toBe(false);
  });
});
