import { createStore } from 'vuex';
import backgroundTasks from '../backgroundTasks';

describe('backgroundTasks', () => {
  let store;
  const task = (id, status = 'running') => ({
    id,
    kind: 'import',
    title: 'Contacts',
    status,
  });
  beforeEach(() => {
    vi.useFakeTimers();
    store = createStore({ modules: { backgroundTasks } });
  });
  afterEach(async () => {
    await store.dispatch('backgroundTasks/reset');
    vi.useRealTimers();
  });

  it('upserts by id and orders running first without mutating insertion order', async () => {
    await store.dispatch('backgroundTasks/upsert', task('1', 'error'));
    await store.dispatch('backgroundTasks/upsert', task('2'));
    await store.dispatch('backgroundTasks/upsert', {
      ...task('1', 'error'),
      detail: 'Invalid file',
    });
    expect(
      store.getters['backgroundTasks/ordered'].map(item => item.id)
    ).toEqual(['2', '1']);
    expect(store.state.backgroundTasks.tasks['1'].detail).toBe('Invalid file');
  });

  it('expires success after ten seconds while errors and running persist', async () => {
    await store.dispatch('backgroundTasks/upsert', task('1', 'success'));
    await store.dispatch('backgroundTasks/upsert', task('2', 'error'));
    await store.dispatch('backgroundTasks/upsert', task('3'));
    await vi.advanceTimersByTimeAsync(9999);
    expect(store.getters['backgroundTasks/ordered']).toHaveLength(3);
    await vi.advanceTimersByTimeAsync(1);
    expect(
      store.getters['backgroundTasks/ordered'].map(item => item.id)
    ).toEqual(['3', '2']);
    await store.dispatch('backgroundTasks/dismiss', '2');
    expect(store.getters['backgroundTasks/ordered']).toEqual([task('3')]);
  });

  it('cancels a success timer on further updates and on account reset', async () => {
    await store.dispatch('backgroundTasks/upsert', task('1', 'success'));
    await store.dispatch('backgroundTasks/upsert', task('1', 'error'));
    await vi.advanceTimersByTimeAsync(10000);
    expect(store.state.backgroundTasks.tasks['1'].status).toBe('error');
    await store.dispatch('backgroundTasks/upsert', task('2', 'success'));
    await store.dispatch('backgroundTasks/reset');
    expect(store.getters['backgroundTasks/ordered']).toEqual([]);
    expect(vi.getTimerCount()).toBe(0);
  });

  it('optimistic track cannot overwrite an event that already finished', async () => {
    await store.dispatch('backgroundTasks/upsert', task('1', 'success'));
    await store.dispatch('backgroundTasks/track', task('1'));
    expect(store.state.backgroundTasks.tasks['1'].status).toBe('success');
  });
});
