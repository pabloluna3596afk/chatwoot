import { nextTick, ref } from 'vue';
import { flushPromises, shallowMount } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import CopilotActionItemsAPI from 'dashboard/api/captain/copilotActionItems';
import CopilotContainer from './CopilotContainer.vue';

const testState = vi.hoisted(() => ({
  dispatch: vi.fn(),
  refs: {},
  uiSettings: null,
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
  const uiSettings = createRef({});
  testState.uiSettings = uiSettings;
  return {
    useUISettings: () => ({
      uiSettings,
      updateUISettings: settings => Object.assign(uiSettings.value, settings),
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
    vi.mocked(useAlert).mockClear();
    testState.refs.getCurrentAccountId.value = 1;
    testState.refs.getSelectedChat.value = { id: 1 };
    testState.refs['captainAssistants/getRecords'].value = [{ id: 7 }];
    testState.uiSettings.value = {
      is_copilot_panel_open: true,
      copilot_unread_count: 2,
    };
  });

  it('minimizes without reopening or clearing the active thread and unread count', async () => {
    testState.uiSettings.value.is_contact_sidebar_open = true;
    testState.uiSettings.value.copilot_active_thread_id = 23;
    const wrapper = mountComponent();
    const copilot = wrapper.findComponent({ name: 'Copilot' });

    await copilot.vm.$emit('minimize');
    await nextTick();

    expect(testState.uiSettings.value).toMatchObject({
      is_copilot_panel_open: false,
      is_contact_sidebar_open: true,
      copilot_active_thread_id: 23,
      copilot_unread_count: 2,
    });
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
  });

  it('minimizes with Escape while preserving the active thread', async () => {
    testState.uiSettings.value.copilot_active_thread_id = 23;
    const wrapper = mountComponent();

    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    await nextTick();

    expect(testState.uiSettings.value).toMatchObject({
      is_copilot_panel_open: false,
      copilot_active_thread_id: 23,
    });
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
  });

  it('keeps the panel minimized when initialized from persisted settings', async () => {
    testState.uiSettings.value.is_copilot_panel_open = false;
    const wrapper = mountComponent();

    await nextTick();

    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(testState.uiSettings.value.is_copilot_panel_open).toBe(false);
  });

  it('keeps the selected thread when the conversation changes', async () => {
    testState.uiSettings.value.copilot_active_thread_id = null;
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

  it('creates a Copilot thread without an assistant id when none is available', async () => {
    testState.refs['captainAssistants/getRecords'].value = [];
    testState.uiSettings.value.copilot_active_thread_id = null;
    testState.dispatch.mockImplementation(action =>
      action === 'copilotThreads/create'
        ? Promise.resolve({ id: 99 })
        : Promise.resolve()
    );
    const wrapper = mountComponent();
    const copilot = wrapper.findComponent({ name: 'Copilot' });

    expect(await copilot.props('onSendMessage')('Help me')).toBe(true);

    expect(testState.dispatch).toHaveBeenCalledWith(
      'copilotThreads/create',
      expect.objectContaining({ message: 'Help me' })
    );
    const createCall = testState.dispatch.mock.calls.find(
      ([action]) => action === 'copilotThreads/create'
    );
    expect(createCall[1]).not.toHaveProperty('assistant_id');
  });

  it('keeps the floating panel available with or without a selected conversation', async () => {
    const wrapper = mountComponent();

    expect(wrapper.find('[role="dialog"]').exists()).toBe(true);

    testState.refs.getSelectedChat.value = null;
    await nextTick();

    expect(wrapper.find('[role="dialog"]').exists()).toBe(true);
  });

  it('retains a thread created while the selected conversation changes', async () => {
    testState.uiSettings.value.copilot_active_thread_id = null;
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
    testState.uiSettings.value.copilot_active_thread_id = null;
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
    testState.uiSettings.value.copilot_active_thread_id = null;
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

  it('starts a new thread when the remembered one no longer exists', async () => {
    testState.uiSettings.value.copilot_active_thread_id = 40;
    const notFound = new Error('');
    notFound.response = { status: 404 };
    testState.dispatch.mockImplementation(action => {
      if (action === 'copilotMessages/create') return Promise.reject(notFound);
      if (action === 'copilotThreads/create')
        return Promise.resolve({ id: 77 });
      return Promise.resolve();
    });
    vi.mocked(CopilotActionItemsAPI.get).mockResolvedValue({ data: [] });
    const wrapper = mountComponent();
    await flushPromises();
    const copilot = wrapper.findComponent({ name: 'Copilot' });

    const result = await copilot.props('onSendMessage')('How many open chats?');

    expect(result).toBe(true);
    expect(testState.dispatch).toHaveBeenCalledWith(
      'copilotThreads/create',
      expect.objectContaining({ message: 'How many open chats?' })
    );
    expect(testState.uiSettings.value.copilot_active_thread_id).toBe(77);
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('still reports other send failures without creating a new thread', async () => {
    testState.uiSettings.value.copilot_active_thread_id = 40;
    testState.dispatch.mockImplementation(action =>
      action === 'copilotMessages/create'
        ? Promise.reject(
            Object.assign(new Error('Server'), { response: { status: 500 } })
          )
        : Promise.resolve()
    );
    const wrapper = mountComponent();
    await flushPromises();
    const copilot = wrapper.findComponent({ name: 'Copilot' });

    const result = await copilot.props('onSendMessage')('Hello');

    expect(result).toBe(false);
    expect(testState.dispatch).not.toHaveBeenCalledWith(
      'copilotThreads/create',
      expect.anything()
    );
  });

  it('silently clears a legacy thread that is missing from the current account', async () => {
    testState.uiSettings.value.copilot_active_thread_id = 23;
    const notFound = new Error('Not found');
    notFound.response = { status: 404 };
    testState.dispatch.mockImplementation(action =>
      action === 'copilotMessages/get'
        ? Promise.reject(notFound)
        : Promise.resolve()
    );

    const wrapper = mountComponent();
    await flushPromises();
    await nextTick();

    expect(testState.dispatch).toHaveBeenCalledWith('copilotMessages/get', 23);
    expect(testState.uiSettings.value).toMatchObject({
      copilot_active_thread_id: null,
      copilot_active_threads: { 1: null },
    });
    expect(useAlert).not.toHaveBeenCalled();
    expect(
      wrapper.findComponent({ name: 'Copilot' }).props('messages')
    ).toEqual([]);

    wrapper.unmount();
    mountComponent();
    await flushPromises();

    expect(
      testState.dispatch.mock.calls.filter(
        ([action]) => action === 'copilotMessages/get'
      )
    ).toEqual([['copilotMessages/get', 23]]);
  });

  it('migrates a valid legacy thread to its account before switching accounts', async () => {
    testState.uiSettings.value.copilot_active_thread_id = 23;
    const wrapper = mountComponent();

    await flushPromises();
    testState.refs.getCurrentAccountId.value = 2;
    await flushPromises();

    expect(testState.uiSettings.value.copilot_active_threads).toEqual({
      1: 23,
    });
    expect(
      testState.dispatch.mock.calls.filter(
        ([action]) => action === 'copilotMessages/get'
      )
    ).toEqual([['copilotMessages/get', 23]]);
    expect(
      wrapper.findComponent({ name: 'Copilot' }).props('messages')
    ).toEqual([]);
  });

  it('restores a different active thread for each account', async () => {
    testState.uiSettings.value.copilot_active_threads = { 1: 23, 2: 45 };
    testState.dispatch.mockResolvedValue(undefined);
    const wrapper = mountComponent();

    await nextTick();
    testState.refs.getCurrentAccountId.value = 2;
    await nextTick();
    await nextTick();

    expect(testState.dispatch).toHaveBeenCalledWith('copilotMessages/get', 23);
    expect(testState.dispatch).toHaveBeenCalledWith('copilotMessages/get', 45);
    expect(
      wrapper.findComponent({ name: 'Copilot' }).props('messages')
    ).toEqual([{ id: 45 }]);
  });
});
