import { flushPromises, mount } from '@vue/test-utils';
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
    vi.restoreAllMocks();
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
      expect(wrapper.classes()).toContain('animate-fade-in-up');
      expect(wrapper.classes()).toContain('motion-reduce:animate-none');
      expect(wrapper.classes()).toContain('border-n-weak');
      expect(wrapper.classes()).toEqual(
        expect.arrayContaining([
          'px-3',
          'py-2',
          'gap-2',
          'rounded-lg',
          'shadow-md',
        ])
      );
      expect(wrapper.get('[title="Contacts"]').classes()).toContain('truncate');
      expect(wrapper.findAll('[title="Contacts"]')).toHaveLength(1);
      expect(wrapper.findComponent(Spinner).exists()).toBe(
        status === 'running'
      );
      if (status === 'running') {
        expect(wrapper.getComponent(Spinner).classes()).toContain(
          'motion-reduce:animate-none'
        );
        expect(wrapper.getComponent(Spinner).classes()).toContain(
          'text-n-brand'
        );
        expect(wrapper.getComponent(Spinner).classes()).toContain('stroke-2');
        expect(wrapper.getComponent(Spinner).props('size')).toBe(16);
        expect(wrapper.get('.stroke-n-blue-5 circle').attributes('r')).toBe(
          '9'
        );
        expect(wrapper.classes()).toContain('border-s-n-brand');
        expect(wrapper.classes()).not.toContain('border-n-brand');
      } else {
        expect(wrapper.classes()).toContain(
          status === 'success' ? 'border-s-n-teal-9' : 'border-s-n-ruby-9'
        );
        expect(wrapper.classes()).not.toContain(
          status === 'success' ? 'border-n-teal-9' : 'border-n-ruby-9'
        );
        expect(wrapper.classes()).toContain(
          status === 'success' ? 'bg-n-teal-2' : 'bg-n-ruby-2'
        );
        expect(wrapper.get('button').attributes('aria-label')).toBe(
          'BACKGROUND_TASKS.CLOSE'
        );
        wrapper.get('button').trigger('click');
        expect(wrapper.emitted('dismiss')).toEqual([['import:1']]);
      }
    }
  );

  it('shows multiple tasks immediately without a capsule and preserves RTL', async () => {
    await store.dispatch('backgroundTasks/upsert', task('running'));
    await store.dispatch('backgroundTasks/upsert', {
      ...task('error'),
      id: 'import:2',
    });
    wrapper = mount(BackgroundTaskTray, {
      global: { plugins: [store, router], stubs: { teleport: true } },
    });
    expect(wrapper.find('[dir="rtl"]').exists()).toBe(true);
    expect(wrapper.get('section').classes()).toEqual(
      expect.arrayContaining([
        'max-w-none',
        'sm:max-w-[18rem]',
        'gap-1.5',
        'p-0',
      ])
    );
    expect(wrapper.findAllComponents(BackgroundTaskItem)).toHaveLength(2);
    expect(wrapper.find('[aria-expanded]').exists()).toBe(false);
    expect(
      wrapper
        .findAllComponents(BackgroundTaskItem)
        .map(item => item.props('task').id)
    ).toEqual(['import:2', 'import:1']);
    await store.dispatch('backgroundTasks/dismiss', 'import:2');
    expect(wrapper.findAllComponents(BackgroundTaskItem)).toHaveLength(1);
  });

  it('limits only running notices to three and counts the rest without hiding errors', async () => {
    const i18n = createI18n({ legacy: false, locale: 'es', messages: { es } });
    await Promise.all(
      Array.from({ length: 5 }, (_, index) =>
        store.dispatch('backgroundTasks/upsert', {
          ...task('running'),
          id: `import:${index + 1}`,
        })
      )
    );
    wrapper = mount(BackgroundTaskTray, {
      global: { plugins: [store, router, i18n], stubs: { teleport: true } },
    });
    expect(wrapper.findAllComponents(BackgroundTaskItem)).toHaveLength(3);
    expect(wrapper.text()).toContain('+2 más');
    await store.dispatch('backgroundTasks/upsert', {
      ...task('error'),
      id: 'error:1',
    });
    await store.dispatch('backgroundTasks/upsert', {
      ...task('error'),
      id: 'error:2',
    });
    const shown = wrapper
      .findAllComponents(BackgroundTaskItem)
      .map(item => item.props('task').id);
    expect(shown).toEqual([
      'error:2',
      'error:1',
      'import:5',
      'import:4',
      'import:3',
    ]);
    expect(wrapper.text()).toContain('+2 más');
    await store.dispatch('backgroundTasks/dismiss', 'import:5');
    expect(
      wrapper
        .findAllComponents(BackgroundTaskItem)
        .map(item => item.props('task').id)
    ).toContain('import:2');
    expect(wrapper.text()).toContain('+1 más');
  });

  it.each(['success', 'error'])(
    'shows every %s even when there are more than three',
    async status => {
      await Promise.all(
        Array.from({ length: 5 }, (_, index) =>
          store.dispatch('backgroundTasks/upsert', {
            ...task(status),
            id: `error:${index + 1}`,
          })
        )
      );
      wrapper = mount(BackgroundTaskTray, {
        global: { plugins: [store, router], stubs: { teleport: true } },
      });
      expect(wrapper.findAllComponents(BackgroundTaskItem)).toHaveLength(5);
      expect(wrapper.find('p[role="status"]').exists()).toBe(false);
    }
  );

  it('keeps a newly successful task visible above three running tasks for ten seconds', async () => {
    await Promise.all(
      Array.from({ length: 4 }, (_, index) =>
        store.dispatch('backgroundTasks/upsert', {
          ...task('running'),
          id: `import:${index + 1}`,
        })
      )
    );
    wrapper = mount(BackgroundTaskTray, {
      global: { plugins: [store, router], stubs: { teleport: true } },
    });
    expect(wrapper.findAllComponents(BackgroundTaskItem)).toHaveLength(3);
    await store.dispatch('backgroundTasks/upsert', task('success'));
    expect(
      wrapper
        .findAllComponents(BackgroundTaskItem)
        .map(item => item.props('task').id)
    ).toEqual(['import:1', 'import:4', 'import:3', 'import:2']);
    expect(wrapper.getComponent(BackgroundTaskItem).props('task').status).toBe(
      'success'
    );
    expect(wrapper.find('p[role="status"]').exists()).toBe(false);
    await vi.advanceTimersByTimeAsync(9999);
    expect(wrapper.getComponent(BackgroundTaskItem).props('task').status).toBe(
      'success'
    );
    await vi.advanceTimersByTimeAsync(1);
    expect(wrapper.findAllComponents(BackgroundTaskItem)).toHaveLength(3);
    expect(
      wrapper
        .findAllComponents(BackgroundTaskItem)
        .every(item => item.props('task').status === 'running')
    ).toBe(true);
  });

  it('keeps notices through navigation and remounting in the same account', async () => {
    await store.dispatch('backgroundTasks/upsert', task('running'));
    router.addRoute({
      path: '/other',
      component: { template: '<p>Other page</p>' },
    });
    await router.push('/');
    wrapper = mount(
      {
        components: { BackgroundTaskTray },
        template: '<BackgroundTaskTray /><router-view />',
      },
      {
        global: { plugins: [store, router], stubs: { teleport: true } },
      }
    );
    const dispatch = vi.spyOn(store, 'dispatch');
    await router.push('/other');
    await flushPromises();
    expect(wrapper.text()).toContain('Other page');
    expect(dispatch).not.toHaveBeenCalledWith('backgroundTasks/reset');
    expect(wrapper.findAllComponents(BackgroundTaskItem)).toHaveLength(1);
    wrapper.unmount();
    wrapper = mount(BackgroundTaskTray, {
      global: { plugins: [store, router], stubs: { teleport: true } },
    });
    expect(wrapper.findAllComponents(BackgroundTaskItem)).toHaveLength(1);
  });

  it('promotes notices above a newly opened native dialog without blocking the rest of the page', async () => {
    const showPopover = vi.fn();
    const hidePopover = vi.fn();
    Object.defineProperty(HTMLElement.prototype, 'showPopover', {
      configurable: true,
      value: showPopover,
    });
    Object.defineProperty(HTMLElement.prototype, 'hidePopover', {
      configurable: true,
      value: hidePopover,
    });
    const dialog = document.createElement('dialog');
    document.body.append(dialog);
    try {
      await store.dispatch('backgroundTasks/upsert', task('running'));
      wrapper = mount(BackgroundTaskTray, {
        global: { plugins: [store, router], stubs: { teleport: true } },
      });
      await flushPromises();
      expect(wrapper.get('section').attributes('popover')).toBe('manual');
      expect(wrapper.get('section').classes()).toContain('z-[10000]');
      expect(wrapper.get('section').classes()).toContain('pointer-events-none');
      expect(wrapper.getComponent(BackgroundTaskItem).classes()).toContain(
        'pointer-events-auto'
      );
      showPopover.mockClear();
      dialog.setAttribute('open', '');
      await flushPromises();
      expect(hidePopover).toHaveBeenCalled();
      expect(showPopover).toHaveBeenCalledOnce();
    } finally {
      dialog.remove();
      delete HTMLElement.prototype.showPopover;
      delete HTMLElement.prototype.hidePopover;
    }
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
    expect(wrapper.get('[role="link"]').attributes('aria-label')).toBe(
      'View import'
    );
    expect(wrapper.text()).not.toContain('View import');
    expect(wrapper.find('button').exists()).toBe(false);
    await wrapper.get('[role="link"]').trigger('click');
    expect(push).toHaveBeenCalledWith({ name: 'home' });
  });

  it('opens the linked card with Enter', async () => {
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
    const card = wrapper.get('[role="link"]');
    expect(card.attributes('tabindex')).toBe('0');
    expect(card.attributes('aria-live')).toBe('polite');
    await card.trigger('keydown', { key: 'Enter' });
    expect(push).toHaveBeenCalledExactlyOnceWith({ name: 'home' });
  });

  it.each(['success', 'error'])(
    'closes %s without opening the linked card',
    async status => {
      const push = vi.spyOn(router, 'push').mockResolvedValue();
      wrapper = mount(BackgroundTaskItem, {
        props: {
          task: {
            ...task(status),
            link: { label: 'View import', route: { name: 'home' } },
          },
        },
        global: { plugins: [router] },
      });
      const close = wrapper.get('button');
      expect(close.classes()).toContain('!size-5');
      await close.trigger('keydown', { key: 'Enter' });
      await close.trigger('click');
      expect(wrapper.emitted('dismiss')).toEqual([['import:1']]);
      expect(push).not.toHaveBeenCalled();
    }
  );

  it('truncates long names and rejection reasons with their full text in native tooltips', () => {
    const title = 'Long template name '.repeat(20);
    const detail = 'Long rejection reason '.repeat(40);
    wrapper = mount(BackgroundTaskItem, {
      props: { task: { ...task('error'), title, detail } },
      global: { plugins: [router] },
    });
    const lines = wrapper.findAll('p');
    expect(lines).toHaveLength(2);
    expect(lines.map(line => line.attributes('title'))).toEqual([
      title,
      detail,
    ]);
    lines.forEach(line => {
      expect(line.classes()).toContain('truncate');
      expect(line.classes()).toContain('leading-4');
      expect(line.classes()).not.toContain('break-words');
    });
  });

  it('renders one text line without detail and remains noninteractive without a link', async () => {
    const push = vi.spyOn(router, 'push').mockResolvedValue();
    wrapper = mount(BackgroundTaskItem, {
      props: { task: { ...task('running'), detail: null } },
      global: { plugins: [router] },
    });
    expect(wrapper.findAll('p')).toHaveLength(1);
    expect(wrapper.attributes('role')).toBe('status');
    expect(wrapper.attributes('tabindex')).toBeUndefined();
    expect(wrapper.classes()).toContain('min-h-11');
    await wrapper.trigger('click');
    expect(push).not.toHaveBeenCalled();
  });
});
