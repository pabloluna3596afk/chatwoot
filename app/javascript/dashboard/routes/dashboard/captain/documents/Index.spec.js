import { flushPromises, shallowMount } from '@vue/test-utils';
import Index from './Index.vue';
import DocumentCard from 'dashboard/components-next/captain/assistant/DocumentCard.vue';

const mocks = vi.hoisted(() => ({
  dispatch: vi.fn(),
  get: vi.fn(),
  alerts: vi.fn(),
  values: {},
}));
vi.mock('dashboard/composables/store', async () => {
  const { ref } = await import('vue');
  mocks.values = {
    'captainDocuments/getRecords': ref([]),
    'captainDocuments/getUIFlags': ref({}),
    'captainDocuments/getMeta': ref({ totalCount: 1, page: 1 }),
  };
  return {
    useStore: () => ({ dispatch: mocks.dispatch }),
    useMapGetter: key => mocks.values[key],
  };
});
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { assistantId: '7' } }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isOnChatwootCloud: false }),
}));
vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({ checkPermissions: () => true }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: mocks.alerts }));
vi.mock('dashboard/api/captain/document', () => ({
  default: { get: mocks.get },
}));
vi.mock('dashboard/components-next/captain/PageLayout.vue', () => ({
  default: { template: '<main><slot name="body" /></main>' },
}));
vi.mock(
  'dashboard/components-next/captain/pageComponents/document/DocumentDetails.vue',
  () => ({ default: { template: '<div />' } })
);
vi.mock(
  'dashboard/components-next/captain/pageComponents/document/CreateDocumentDialog.vue',
  () => ({ default: { template: '<div />' } })
);

const mountPage = async () => {
  const wrapper = shallowMount(Index, {
    global: {
      stubs: {
        PageLayout: { template: '<main><slot name="body" /></main>' },
      },
    },
  });
  await flushPromises();
  return wrapper;
};

beforeEach(() => {
  mocks.values['captainDocuments/getRecords'].value = [
    {
      id: 42,
      external_link: 'https://example.com/help',
      created_at: 1_700_000_000,
      status: 'in_progress',
      quota_exceeded: true,
    },
  ];
  mocks.get.mockResolvedValue({
    data: {
      payload: mocks.values['captainDocuments/getRecords'].value,
      meta: {},
    },
  });
});

it('passes the serialized quota state to the card and refreshes after Continue', async () => {
  let resolve;
  mocks.dispatch.mockImplementation(action =>
    action === 'captainDocuments/resume'
      ? new Promise(done => {
          resolve = done;
        })
      : Promise.resolve()
  );
  const wrapper = await mountPage();
  const card = wrapper.getComponent(DocumentCard);
  expect(card.props('quotaExceeded')).toBe(true);
  card.vm.$emit('action', { action: 'resume', id: 42 });
  card.vm.$emit('action', { action: 'resume', id: 42 });
  await flushPromises();
  expect(
    mocks.dispatch.mock.calls.filter(
      ([action]) => action === 'captainDocuments/resume'
    )
  ).toEqual([['captainDocuments/resume', 42]]);
  resolve();
  await flushPromises();
  expect(mocks.alerts).toHaveBeenCalledWith(
    'CAPTAIN.DOCUMENTS.RESUME.SUCCESS_MESSAGE'
  );
  expect(mocks.get.mock.calls.length).toBeGreaterThan(1);
  wrapper.unmount();
});

it('shows the server quota error and allows a later retry', async () => {
  mocks.dispatch.mockImplementation(action =>
    action === 'captainDocuments/resume'
      ? Promise.reject(new Error('Not enough internal actions'))
      : Promise.resolve()
  );
  const wrapper = await mountPage();
  wrapper
    .getComponent(DocumentCard)
    .vm.$emit('action', { action: 'resume', id: 42 });
  await flushPromises();
  expect(mocks.alerts).toHaveBeenCalledWith('Not enough internal actions');
  expect(mocks.get).toHaveBeenCalledTimes(1);
  wrapper
    .getComponent(DocumentCard)
    .vm.$emit('action', { action: 'resume', id: 42 });
  await flushPromises();
  expect(
    mocks.dispatch.mock.calls.filter(
      ([action]) => action === 'captainDocuments/resume'
    )
  ).toHaveLength(2);
  wrapper.unmount();
});

it('includes resumed documents in polling until completion or another quota pause', async () => {
  const wrapper = await mountPage();
  expect(wrapper.vm.hasDocumentsSyncing).toBe(false);
  mocks.values['captainDocuments/getRecords'].value = [
    { id: 42, status: 'in_progress', quota_exceeded: false },
  ];
  await flushPromises();
  expect(wrapper.vm.hasDocumentsSyncing).toBe(true);
  mocks.values['captainDocuments/getRecords'].value = [
    { id: 42, status: 'available', quota_exceeded: false },
  ];
  await flushPromises();
  expect(wrapper.vm.hasDocumentsSyncing).toBe(false);
  wrapper.unmount();
});
