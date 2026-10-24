vi.mock('dashboard/components/policy.vue', () => ({
  default: { template: '<span><slot /></span>' },
}));
vi.mock('dashboard/composables/usePolicy', () => ({ usePolicy: () => ({}) }));
vi.mock('dashboard/components-next/captain/PageLayout.vue', () => ({
  default: { template: '<div><slot name="body" /></div>' },
}));
vi.mock(
  'dashboard/components-next/captain/pageComponents/assistant/settings/SettingsPageLayout.vue',
  () => ({ default: { template: '<div><slot /></div>' } })
);
vi.mock('dashboard/components-next/Editor/Editor.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock('@amplitude/analytics-browser', () => ({}));
import { flushPromises, shallowMount } from '@vue/test-utils';
import Guidelines from './guidelines/Index.vue';
import Guardrails from './guardrails/Index.vue';
import Scenarios from './scenarios/Index.vue';
import AddNewRulesDialog from 'dashboard/components-next/captain/assistant/AddNewRulesDialog.vue';
import AddNewScenariosDialog from 'dashboard/components-next/captain/assistant/AddNewScenariosDialog.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const mocks = vi.hoisted(() => ({
  dispatch: vi.fn(),
  alert: vi.fn(),
  close: vi.fn(),
  open: vi.fn(),
  assistant: null,
  assistantId: null,
}));
vi.mock('dashboard/composables/store', async () => {
  const { ref: makeRef } = await import('vue');
  return {
    useStore: () => ({ dispatch: mocks.dispatch }),
    useMapGetter: key => makeRef(key.includes('UIFlags') ? {} : []),
  };
});
vi.mock('dashboard/composables', () => ({ useAlert: mocks.alert }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { assistantId: 7 } }),
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ uiSettings: {}, updateUISettings: vi.fn() }),
}));
vi.mock('./settings/useAssistantSettings', async () => {
  const { ref: makeRef } = await import('vue');
  return {
    useAssistantSettings: () => {
      mocks.assistantId = makeRef(7);
      mocks.assistant = makeRef({
        response_guidelines: ['A', 'B'],
        guardrails: ['A', 'B'],
      });
      return { assistantId: mocks.assistantId, assistant: mocks.assistant };
    },
  };
});
vi.mock('shared/composables/useMessageFormatter', () => ({
  useMessageFormatter: () => ({ formatMessage: text => text }),
}));
const slots = {
  template:
    '<div><slot /><slot name="body" /><slot name="default-actions" /></div>',
};
const mountPage = Component =>
  shallowMount(Component, {
    global: {
      directives: { 'dompurify-html': {} },
      stubs: {
        PageLayout: slots,
        SettingsPageLayout: slots,
        BulkSelectBar: slots,
        Dialog: {
          methods: { open: mocks.open, close: mocks.close },
          template: '<div><slot /></div>',
        },
      },
    },
  });

beforeEach(() => {
  vi.clearAllMocks();
  mocks.dispatch.mockResolvedValue({});
});

describe.each([Guidelines, Guardrails, Scenarios])(
  'Captain mutation owner',
  Component => {
    it.each([new Error('Network error'), { response: { status: 422 } }])(
      'returns failure for %s and allows retry',
      async error => {
        const wrapper = mountPage(Component);
        mocks.dispatch.mockRejectedValueOnce(error);
        const form = wrapper.findComponent(
          Component === Scenarios ? AddNewScenariosDialog : AddNewRulesDialog
        );
        expect(form.exists()).toBe(true);
        const draft =
          Component === Scenarios
            ? { title: 'New', instruction: 'Instruction' }
            : 'New';
        expect(await form.props('onAdd')(draft)).toBe(false);
        expect(await form.props('onAdd')(draft)).toBe(true);
        wrapper.unmount();
      }
    );

    it('does not delete on request/cancel and retains confirmation after failure', async () => {
      const wrapper = mountPage(Component);
      mocks.dispatch.mockClear();
      wrapper.vm.requestDelete([0, 1]);
      expect(mocks.open).toHaveBeenCalledOnce();
      expect(mocks.dispatch).not.toHaveBeenCalled();
      // Closing without confirming has no mutation handler.
      wrapper.findComponent(Dialog).vm.$emit('close');
      expect(mocks.dispatch).not.toHaveBeenCalled();
      mocks.dispatch.mockRejectedValue(new Error('Network error'));
      wrapper.findComponent(Dialog).vm.$emit('confirm');
      await flushPromises();
      expect(mocks.close).not.toHaveBeenCalled();
      expect(wrapper.vm.deleteIds).toEqual([0, 1]);
      wrapper.unmount();
    });
  }
);

describe.each([
  [Guidelines, 'response_guidelines'],
  [Guardrails, 'guardrails'],
])('Rule list contract', (Component, field) => {
  it('does not replace another assistant snapshot when a previous save finishes', async () => {
    const wrapper = mountPage(Component);
    let resolve;
    mocks.dispatch.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const save = wrapper.findComponent(AddNewRulesDialog).props('onAdd')(
      'Draft'
    );
    mocks.assistantId.value = 8;
    mocks.assistant.value[field] = ['Another assistant'];
    await flushPromises();
    resolve();
    await save;
    await wrapper.findComponent(AddNewRulesDialog).props('onAdd')('Next');
    expect(mocks.dispatch).toHaveBeenLastCalledWith(
      'captainAssistants/update',
      {
        id: 8,
        assistant: {
          [field]: ['Another assistant', 'Next'],
          [`expected_${field}`]: ['Another assistant'],
        },
      }
    );
    wrapper.unmount();
  });

  it('retains the original snapshot when another consumer refreshes the shared store', async () => {
    const wrapper = mountPage(Component);
    mocks.assistant.value[field] = ['Changed elsewhere'];
    await flushPromises();
    await wrapper.findComponent(AddNewRulesDialog).props('onAdd')('Draft');
    expect(mocks.dispatch).toHaveBeenLastCalledWith(
      'captainAssistants/update',
      {
        id: 7,
        assistant: {
          [field]: ['A', 'B', 'Draft'],
          [`expected_${field}`]: ['A', 'B'],
        },
      }
    );
    wrapper.unmount();
  });

  it('sends the original list, preserves the draft on conflict and advances only after success', async () => {
    const wrapper = mountPage(Component);
    const form = wrapper.findComponent(AddNewRulesDialog);
    mocks.dispatch.mockRejectedValueOnce(
      new Error('Reload and review your draft')
    );
    expect(await form.props('onAdd')('Draft')).toBe(false);
    expect(wrapper.get('[role="alert"]').text()).toBe(
      'Reload and review your draft'
    );
    expect(mocks.dispatch).toHaveBeenLastCalledWith(
      'captainAssistants/update',
      {
        id: 7,
        assistant: {
          [field]: ['A', 'B', 'Draft'],
          [`expected_${field}`]: ['A', 'B'],
        },
      }
    );
    expect(await form.props('onAdd')('Draft')).toBe(true);
    expect(await form.props('onAdd')('Next')).toBe(true);
    expect(mocks.dispatch).toHaveBeenLastCalledWith(
      'captainAssistants/update',
      {
        id: 7,
        assistant: {
          [field]: ['A', 'B', 'Draft', 'Next'],
          [`expected_${field}`]: ['A', 'B', 'Draft'],
        },
      }
    );
    wrapper.unmount();
  });
});

it('reports partial scenario deletion and retries only failures, once per intention', async () => {
  const wrapper = mountPage(Scenarios);
  mocks.dispatch.mockClear();
  wrapper.vm.requestDelete([1, 2]);
  mocks.dispatch.mockImplementation((_action, { id }) =>
    id === 2 ? Promise.reject(new Error('422')) : Promise.resolve()
  );
  const first = wrapper.vm.bulkDeleteScenarios();
  await wrapper.vm.bulkDeleteScenarios();
  await first;
  expect(mocks.dispatch).toHaveBeenCalledTimes(2);
  expect(wrapper.vm.deleteIds).toEqual([2]);
  expect(wrapper.vm.deleteError).toBeTruthy();
  expect(mocks.close).not.toHaveBeenCalled();
  mocks.dispatch.mockClear().mockResolvedValue(undefined);
  await wrapper.vm.bulkDeleteScenarios();
  expect(mocks.dispatch).toHaveBeenCalledExactlyOnceWith(
    'captainScenarios/delete',
    { id: 2, assistantId: 7 }
  );
  expect(mocks.close).toHaveBeenCalledOnce();
  wrapper.unmount();
});
