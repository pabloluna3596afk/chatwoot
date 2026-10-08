import { flushPromises, mount } from '@vue/test-utils';
import FlowPublicationPanel from '../FlowPublicationPanel.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import { useAlert } from 'dashboard/composables';
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
const SidePanelStub = {
  template: '<div><slot/><slot name="footer"/></div>',
  methods: { open() {}, close() {} },
};
const row = {
  waba_id: '111',
  state: 'error',
  numbers: [{ channel_id: 7, inbox_name: 'Quito', phone_number: '+593990001' }],
  validation_errors: [{ message: 'Invalid option' }],
};
const flow = {
  id: 4,
  name: 'Datos',
  publication_summary: {
    state: 'error',
    total: 120,
    published: 108,
    errors: 2,
  },
};
let wrapper;
let api;
beforeEach(async () => {
  vi.useFakeTimers();
  api = {
    publicationStatus: vi.fn().mockResolvedValue({
      data: {
        rows: [row],
        meta: { total_count: 120 },
        publication_summary: flow.publication_summary,
      },
    }),
    retryPublication: vi.fn().mockResolvedValue({}),
  };
  wrapper = mount(FlowPublicationPanel, {
    props: { api },
    global: { stubs: { SidePanel: SidePanelStub } },
  });
  expect(api.publicationStatus).not.toHaveBeenCalled();
  wrapper.vm.open(flow);
  await flushPromises();
  await vi.advanceTimersByTimeAsync(201);
  await flushPromises();
  await flushPromises();
});
afterEach(() => {
  vi.useRealTimers();
  wrapper.unmount();
});
describe('FlowPublicationPanel', () => {
  it('shows cached rows immediately while refreshing, without a spinner or debounce on open', async () => {
    let finish;
    api.publicationStatus.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const calls = api.publicationStatus.mock.calls.length;
    wrapper.vm.open(flow);
    expect(api.publicationStatus).toHaveBeenCalledTimes(calls + 1);
    await flushPromises();
    expect(wrapper.findAll('[data-testid="waba-row"]')).toHaveLength(1);
    expect(wrapper.findComponent({ name: 'Spinner' }).exists()).toBe(false);
    await vi.advanceTimersByTimeAsync(1000);
    expect(wrapper.get('[data-testid="waba-row"]').text()).toContain('Quito');
    finish({
      data: {
        rows: [
          { ...row, numbers: [{ ...row.numbers[0], inbox_name: 'Updated' }] },
        ],
        meta: { total_count: 1 },
        publication_summary: flow.publication_summary,
      },
    });
    await flushPromises();
    expect(wrapper.get('[data-testid="waba-row"]').text()).toContain('Updated');
  });

  it('never displays cached rows belonging to a different Flow', async () => {
    api.publicationStatus.mockImplementationOnce(() => new Promise(() => {}));
    wrapper.vm.open({ ...flow, id: 99 });
    await flushPromises();
    expect(wrapper.findAll('[data-testid="waba-row"]')).toHaveLength(0);
  });

  it('loads one WABA page on demand and displays numbers, state and reason', () => {
    expect(api.publicationStatus).toHaveBeenCalledWith(
      4,
      { page: 1, per_page: 5 },
      expect.objectContaining({ signal: expect.any(Object) })
    );
    expect(wrapper.findAll('[data-testid="waba-row"]')).toHaveLength(1);
    expect(wrapper.text()).toContain('Quito');
    expect(wrapper.text()).toContain('+593990001');
    expect(wrapper.text()).toContain('Invalid option');
  });
  it('searches and filters on the server and resets pagination', async () => {
    wrapper.findComponent(PaginationFooter).vm.$emit('update:currentPage', 3);
    await flushPromises();
    await vi.advanceTimersByTimeAsync(201);
    await flushPromises();
    await wrapper.get('[data-testid="waba-search"] input').setValue('Cuenca');
    wrapper.findComponent(ComboBox).vm.$emit('update:modelValue', 'error');
    await flushPromises();
    await vi.advanceTimersByTimeAsync(201);
    await flushPromises();
    expect(api.publicationStatus).toHaveBeenLastCalledWith(
      4,
      { page: 1, per_page: 5, search: 'Cuenca', state: 'error' },
      expect.any(Object)
    );
  });
  it('requests the next page', async () => {
    wrapper.findComponent(PaginationFooter).vm.$emit('update:currentPage', 2);
    await flushPromises();
    await vi.advanceTimersByTimeAsync(201);
    await flushPromises();
    expect(api.publicationStatus).toHaveBeenLastCalledWith(
      4,
      { page: 2, per_page: 5 },
      expect.any(Object)
    );
  });
  it('retries only the chosen failed WABA and refreshes the detail', async () => {
    await wrapper.get('[data-testid="waba-retry"]').trigger('click');
    await flushPromises();
    expect(api.retryPublication).toHaveBeenCalledWith(4, '111');
    expect(api.publicationStatus).toHaveBeenCalledTimes(2);
    expect(wrapper.emitted('updated')).toHaveLength(2);
    expect(useAlert).toHaveBeenCalled();
  });
  it('notifies the catalog after reading the latest publication state', async () => {
    api.publicationStatus.mockResolvedValueOnce({
      data: {
        rows: [{ ...row, state: 'published' }],
        meta: { total_count: 1 },
        publication_summary: {
          state: 'published',
          total: 1,
          published: 1,
          errors: 0,
        },
      },
    });
    wrapper.vm.open(flow);
    await flushPromises();
    await vi.advanceTimersByTimeAsync(201);
    await flushPromises();
    expect(wrapper.emitted('updated')).toHaveLength(2);
    expect(wrapper.get('[data-testid="waba-row"]').text()).toContain(
      'WHATSAPP_FLOWS.META.STATE.published'
    );
  });
  it('includes retired WABAs only in detail and offers retry for blocked/throttled', async () => {
    api.publicationStatus.mockResolvedValueOnce({
      data: {
        rows: ['deprecated', 'blocked', 'throttled'].map((state, index) => ({
          ...row,
          waba_id: String(index + 1),
          state,
        })),
        meta: { total_count: 3 },
        publication_summary: flow.publication_summary,
      },
    });
    wrapper.vm.open(flow);
    await flushPromises();
    await vi.advanceTimersByTimeAsync(201);
    await flushPromises();
    expect(wrapper.findAll('[data-testid="waba-retry"]')).toHaveLength(2);
    expect(wrapper.findAll('[data-testid="waba-row"]')).toHaveLength(3);
  });
});
