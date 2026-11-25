import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createRouter, createMemoryHistory } from 'vue-router';
import backgroundTasks from 'dashboard/store/modules/backgroundTasks';
import BackgroundTaskTray from '../BackgroundTaskTray.vue';
import BackgroundTaskItem from '../BackgroundTaskItem.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { useBackgroundTasks } from 'dashboard/composables/useBackgroundTasks';
import { createI18n } from 'vue-i18n';
import es from 'dashboard/i18n/locale/es/backgroundTasks.json';
import en from 'dashboard/i18n/locale/en/backgroundTasks.json';

describe('background task tray', () => {
  let store;
  let router;
  let wrapper;
  const task = status => ({
    id: 'import:1',
    kind: 'import',
    title: 'Contacts',
    status,
    detail: 'Importing contacts',
  });
  beforeEach(() => {
    vi.useFakeTimers();
    store = createStore({
      modules: { backgroundTasks },
      state: { accountId: 1 },
      getters: {
        getCurrentAccountId: state => state.accountId,
        'accounts/isRTL': () => true,
      },
    });
    router = createRouter({
      history: createMemoryHistory(),
      routes: [{ path: '/', name: 'home', component: { template: '<div />' } }],
    });
  });
  afterEach(() => {
    wrapper?.unmount();
    store.dispatch('backgroundTasks/reset');
    vi.useRealTimers();
  });

  it('renders nothing for an empty store', () => {
    wrapper = mount(BackgroundTaskTray, {
      global: { plugins: [store, router], stubs: { teleport: true } },
    });
    expect(wrapper.find('section').exists()).toBe(false);
  });

  it.each(['running', 'success', 'error'])(
    'renders accessible %s notices',
    status => {
      wrapper = mount(BackgroundTaskItem, {
        props: { task: task(status) },
        global: { plugins: [router] },
      });
      expect(wrapper.get('[role="status"]').attributes('aria-live')).toBe(
        'polite'
      );
      expect(wrapper.text()).toContain('Contacts');
      expect(wrapper.text()).toContain('Importing contacts');
      expect(wrapper.findComponent(Spinner).exists()).toBe(
        status === 'running'
      );
      if (status === 'running')
        expect(wrapper.getComponent(Spinner).classes()).toContain(
          'motion-reduce:animate-none'
        );
      else {
        expect(wrapper.classes()).toContain(
          status === 'success' ? 'border-n-teal-9' : 'border-n-ruby-9'
        );
        expect(wrapper.get('button').attributes('aria-label')).toBe(
          'BACKGROUND_TASKS.CLOSE'
        );
        wrapper.get('button').trigger('click');
        expect(wrapper.emitted('dismiss')).toEqual([['import:1']]);
      }
    }
  );

  it('folds multiple tasks, expands with a button, and preserves RTL', async () => {
    const i18n = createI18n({ legacy: false, locale: 'es', messages: { es } });
    await store.dispatch('backgroundTasks/upsert', task('running'));
    await store.dispatch('backgroundTasks/upsert', {
      ...task('error'),
      id: 'import:2',
    });
    wrapper = mount(BackgroundTaskTray, {
      global: { plugins: [store, router, i18n], stubs: { teleport: true } },
    });
    expect(wrapper.find('[dir="rtl"]').exists()).toBe(true);
    expect(wrapper.findAllComponents(BackgroundTaskItem)).toHaveLength(0);
    const capsule = wrapper.get('button');
    expect(capsule.text()).toBe('2 tareas en segundo plano');
    expect(capsule.attributes('aria-expanded')).toBe('false');
    await capsule.trigger('click');
    expect(wrapper.findAllComponents(BackgroundTaskItem)).toHaveLength(2);
    expect(wrapper.get('button').attributes('aria-expanded')).toBe('true');
    await store.dispatch('backgroundTasks/dismiss', 'import:2');
    expect(wrapper.findAllComponents(BackgroundTaskItem)).toHaveLength(1);
  });

  it('keeps English and Spanish translation keys in parity without CJK text', () => {
    expect(Object.keys(es.BACKGROUND_TASKS)).toEqual(
      Object.keys(en.BACKGROUND_TASKS)
    );
    expect(JSON.stringify({ en, es })).not.toMatch(
      /[\u3400-\u9fff\u3040-\u30ff\uac00-\ud7af]/u
    );
    expect(en.BACKGROUND_TASKS.SENDING).toBe('Sending to Meta…');
    expect(es.BACKGROUND_TASKS.REVIEW).toBe('En revisión de Meta');
  });

  it('clears tasks when switching accounts', async () => {
    await store.dispatch('backgroundTasks/upsert', task('running'));
    wrapper = mount(BackgroundTaskTray, {
      global: { plugins: [store, router], stubs: { teleport: true } },
    });
    store.state.accountId = 2;
    await wrapper.vm.$nextTick();
    expect(store.getters['backgroundTasks/ordered']).toEqual([]);
  });

  it('navigates optional links and works with the generic composable', async () => {
    let api;
    wrapper = mount(
      {
        setup() {
          api = useBackgroundTasks();
          return {};
        },
        template: '<div />',
      },
      { global: { plugins: [store] } }
    );
    await api.track(task('running'));
    await api.update(task('success'));
    expect(store.state.backgroundTasks.tasks['import:1'].status).toBe(
      'success'
    );
    wrapper.unmount();
    const push = vi.spyOn(router, 'push').mockResolvedValue();
    wrapper = mount(BackgroundTaskItem, {
      props: {
        task: {
          ...task('running'),
          link: { label: 'View import', route: { name: 'home' } },
        },
      },
      global: { plugins: [router] },
    });
    await wrapper.get('button').trigger('click');
    expect(push).toHaveBeenCalledWith({ name: 'home' });
  });
});
