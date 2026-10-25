import { mount, flushPromises } from '@vue/test-utils';
import CompanyAPI from 'dashboard/api/companies';
import CompanySelector from '../CompanySelector.vue';

vi.mock('dashboard/api/companies', () => ({
  default: { get: vi.fn(), search: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

afterEach(() => vi.useRealTimers());

it('retains the linked company and typed query after a failed request and retries explicitly', async () => {
  vi.useFakeTimers();
  CompanyAPI.get.mockResolvedValue({
    data: { payload: [{ id: 7, name: 'Linked' }] },
  });
  let rejectSearch;
  CompanyAPI.search.mockImplementationOnce(
    () =>
      new Promise((resolve, reject) => {
        rejectSearch = reject;
      })
  );
  const wrapper = mount(CompanySelector, {
    props: { modelValue: 7, selectedName: 'Linked' },
    global: { stubs: { CompanyCreateDialog: true } },
  });
  await wrapper.get('button').trigger('click');
  await flushPromises();
  const input = wrapper.get('input');
  await input.setValue('customer');
  await vi.advanceTimersByTimeAsync(300);
  expect(wrapper.get('[aria-busy="true"]').exists()).toBe(true);
  rejectSearch(new Error('offline'));
  await flushPromises();
  expect(wrapper.get('[role="alert"]').text()).toBe('COMBOBOX.SEARCH_ERROR');
  expect(wrapper.get('button').text()).toBe('Linked');
  expect(input.element.value).toBe('customer');
  expect(wrapper.emitted('select')).toBeUndefined();
  await vi.advanceTimersByTimeAsync(1000);
  expect(CompanyAPI.search).toHaveBeenCalledTimes(1);
  CompanyAPI.search.mockResolvedValue({
    data: { payload: [{ id: 8, name: 'Customer' }] },
  });
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'COMBOBOX.RETRY')
    .trigger('click');
  await vi.advanceTimersByTimeAsync(300);
  await flushPromises();
  expect(CompanyAPI.search).toHaveBeenLastCalledWith('customer');
  expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  expect(input.element.value).toBe('customer');
  expect(wrapper.get('button').text()).toBe('Linked');
  wrapper.unmount();
});
