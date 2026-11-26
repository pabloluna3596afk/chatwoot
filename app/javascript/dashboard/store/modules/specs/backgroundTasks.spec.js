import { createStore } from 'vuex';
import backgroundTasks from '../backgroundTasks';

describe('backgroundTasks', () => {
  let store;
  const task = (id, status = 'running', phase = 'running') => ({
    id,
    kind: 'import',
    title: 'Contacts',
    status,
    phase,
  });
  beforeEach(() => {
    vi.useFakeTimers();
    store = createStore({ modules: { backgroundTasks } });
  });
  afterEach(() => vi.useRealTimers());

  it('updates a task in place without changing its position as progress changes', async () => {
    await store.dispatch('backgroundTasks/upsert', task('a'));
    await store.dispatch('backgroundTasks/upsert', task('b'));
    await store.dispatch('backgroundTasks/upsert', {
      ...task('a'),
      detail: '320/800',
    });
    expect(
      store.getters['backgroundTasks/ordered'].map(item => item.id)
    ).toEqual(['b', 'a']);
    expect(store.state.backgroundTasks.tasks.a.detail).toBe('320/800');
  });

  it('keeps successful and failed results until explicitly removed', async () => {
    await store.dispatch(
      'backgroundTasks/upsert',
      task('success', 'success', null)
    );
    await store.dispatch(
      'backgroundTasks/upsert',
      task('error', 'error', null)
    );
    await vi.advanceTimersByTimeAsync(24 * 60 * 60 * 1000);
    expect(
      store.getters['backgroundTasks/ordered'].map(item => item.id)
    ).toEqual(['error', 'success']);
    await store.dispatch('backgroundTasks/dismiss', 'success');
    expect(
      store.getters['backgroundTasks/ordered'].map(item => item.id)
    ).toEqual(['error']);
  });

  it('preserves the explicit waiting phase', async () => {
    await store.dispatch(
      'backgroundTasks/upsert',
      task('meta', 'running', 'waiting')
    );
    expect(store.getters['backgroundTasks/ordered'][0]).toMatchObject({
      status: 'running',
      phase: 'waiting',
    });
  });

  it('retains only the latest twenty finished results while keeping active tasks', async () => {
    await store.dispatch('backgroundTasks/upsert', task('active'));
    await Promise.all(
      Array.from({ length: 21 }, (_, id) =>
        store.dispatch(
          'backgroundTasks/upsert',
          task(`result-${id}`, 'success', null)
        )
      )
    );
    expect(store.getters['backgroundTasks/ordered']).toHaveLength(21);
    expect(store.getters['backgroundTasks/ordered'][0].id).toBe('result-20');
    expect(store.state.backgroundTasks.tasks['result-0']).toBeUndefined();
    expect(store.state.backgroundTasks.tasks.active).toBeDefined();
  });
});
