import { defineComponent, h, ref } from 'vue';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import { mount } from '@vue/test-utils';
import ActivityButton from '../ActivityButton.vue';
import backgroundTasks from 'dashboard/store/modules/backgroundTasks';
import en from 'dashboard/i18n/locale/en/backgroundTasks.json';

vi.mock('dashboard/components-next/popover/Popover.vue', () => ({
  default: defineComponent({
    emits: ['show', 'hide'],
    setup(_, { emit, expose, slots }) {
      const visible = ref(false);
      const show = () => {
        visible.value = true;
        emit('show');
      };
      const hide = () => {
        visible.value = false;
        emit('hide');
      };
      const toggle = () => (visible.value ? hide() : show());
      expose({ show, hide });
      return () =>
        h('div', { onClick: toggle }, [
          slots.default?.(),
          visible.value ? slots.content?.({ hide, isMobile: false }) : null,
        ]);
    },
  }),
}));

const messages = { en };
const task = (id, status, phase = null) => ({
  id,
  kind: 'import',
  title: id,
  status,
  phase,
  version: 1,
  link: { route: { name: 'home' } },
});

describe('ActivityButton', () => {
  let store;
  let wrapper;
  beforeEach(() => {
    localStorage.clear();
    store = createStore({
      modules: { backgroundTasks },
      getters: {
        getCurrentAccountId: () => 1,
        getCurrentUser: () => ({ id: 9 }),
      },
    });
  });
  afterEach(() => {
    wrapper?.unmount();
    vi.restoreAllMocks();
  });

  const render = () => {
    const i18n = createI18n({ legacy: false, locale: 'en', messages });
    wrapper = mount(ActivityButton, {
      global: {
        plugins: [store, i18n],
        stubs: { RouterLink: { template: '<a><slot /></a>' } },
      },
    });
  };

  it('shows a stable activity entry at rest and reflects task priority', async () => {
    render();
    const button = wrapper.get('button');
    expect(button.attributes('aria-haspopup')).toBe('dialog');
    expect(button.attributes('aria-label')).toContain('No recent activity');
    await store.dispatch(
      'backgroundTasks/upsert',
      task('wait', 'running', 'waiting')
    );
    expect(button.text()).toContain('1');
    await store.dispatch('backgroundTasks/upsert', task('error', 'error'));
    expect(button.attributes('aria-label')).toContain('1 new errors');
    expect(wrapper.find('.text-n-ruby-11').exists()).toBe(true);
  });

  it('marks recovered results as seen on open without dismissing them', async () => {
    await store.dispatch('backgroundTasks/upsert', task('done', 'success'));
    render();
    await wrapper.get('button').trigger('click');
    expect(wrapper.text()).toContain('done');
    expect(localStorage.getItem('activity-seen:9:1')).toContain('"done":"1"');
    expect(store.getters['backgroundTasks/ordered']).toHaveLength(1);
  });

  it('shows loading, empty, and recovery failure as distinct states', async () => {
    store.commit('backgroundTasks/setLoading', true);
    render();
    await wrapper.get('button').trigger('click');
    expect(wrapper.text()).toContain('Checking activity');
    await wrapper.get('button').trigger('click');
    store.commit('backgroundTasks/setLoading', false);
    store.commit('backgroundTasks/setFailed', true);
    await wrapper.get('button').trigger('click');
    expect(wrapper.text()).toContain("We couldn't update activity.");
    expect(wrapper.get('button').attributes('aria-label')).toContain(
      "We couldn't update activity."
    );
    store.commit('backgroundTasks/setFailed', false);
    await wrapper.get('button').trigger('click');
    await wrapper.get('button').trigger('click');
    expect(wrapper.text()).toContain('No recent tasks.');
  });

  it('keeps activity usable when local storage is blocked', async () => {
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('Storage blocked');
    });
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('Storage blocked');
    });
    await store.dispatch('backgroundTasks/upsert', task('failed', 'error'));
    render();
    await wrapper.get('button').trigger('click');
    expect(wrapper.text()).toContain('failed');
    expect(store.getters['backgroundTasks/ordered']).toHaveLength(1);
  });
});
