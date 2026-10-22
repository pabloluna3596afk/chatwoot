import { effectScope, ref, nextTick } from 'vue';
import { flushPromises } from '@vue/test-utils';
import { useAppointmentEvents } from '../useAppointmentEvents';

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId: ref(1) }),
}));

it('waits for a connected calendar, aborts when disabled and ignores the old response', async () => {
  const enabled = ref(false);
  const context = ref(7);
  let resolve;
  let signal;
  const fetchEvents = vi.fn(requestSignal => {
    signal = requestSignal;
    return new Promise(done => {
      resolve = done;
    });
  });
  const scope = effectScope();
  const result = scope.run(() =>
    useAppointmentEvents({
      context,
      contactId: () => context.value,
      enabled,
      fetchEvents,
    })
  );
  expect(fetchEvents).not.toHaveBeenCalled();
  enabled.value = true;
  await nextTick();
  expect(fetchEvents).toHaveBeenCalledTimes(1);
  enabled.value = false;
  await nextTick();
  expect(signal.aborted).toBe(true);
  resolve({ data: { payload: [{ id: 'stale' }] } });
  await flushPromises();
  expect(result.events.value).toEqual([]);
  expect(result.hasError.value).toBe(false);
  enabled.value = true;
  await nextTick();
  resolve({ data: { payload: [{ id: 'fresh' }] } });
  await flushPromises();
  expect(result.events.value).toEqual([{ id: 'fresh' }]);
  scope.stop();
});
