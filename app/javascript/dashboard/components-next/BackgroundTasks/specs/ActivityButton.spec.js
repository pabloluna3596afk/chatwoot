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
        h(
          'div',
          {
            onClick: event => {
              if (
                event.target.closest(
                  '[aria-controls="background-activity-panel"]'
                )
              )
                toggle();
            },
          },
          [
            slots.default?.(),
            visible.value ? slots.content?.({ hide, isMobile: false }) : null,
          ]
        );
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

  it('does not render an activity strip at rest', () => {
    render();
    expect(wrapper.find('button').exists()).toBe(false);
  });

  it('shows one compact trigger with status priority and accessible text', async () => {
    await store.dispatch(
      'backgroundTasks/upsert',
      task('waiting', 'running', 'waiting')
    );
    render();
    const button = wrapper.get('button');
    expect(button.attributes('aria-haspopup')).toBe('dialog');
    expect(button.attributes('aria-expanded')).toBe('false');
    expect(button.attributes('aria-label')).toContain('1 waiting');
    await store.dispatch('backgroundTasks/upsert', task('error', 'error'));
    expect(button.attributes('aria-label')).toContain('1 new error');
    expect(wrapper.find('.text-n-ruby-11').exists()).toBe(true);
  });

  it('summarizes ten new errors in a collapsed icon trigger', async () => {
    await Promise.all(
      Array.from({ length: 10 }, (_, index) =>
        store.dispatch(
          'backgroundTasks/upsert',
          task(`error-${index}`, 'error')
        )
      )
    );
    const i18n = createI18n({ legacy: false, locale: 'en', messages });
    wrapper = mount(ActivityButton, {
      props: { collapsed: true },
      global: {
        plugins: [store, i18n],
        stubs: { RouterLink: { template: '<a><slot /></a>' } },
      },
    });
    const button = wrapper.get('button');
    expect(button.text()).toBe('');
    expect(button.attributes('title')).toContain('10 new errors');
  });

  it('marks result rows seen on open and removes them after close', async () => {
    await store.dispatch('backgroundTasks/upsert', task('done', 'success'));
    render();
    await wrapper.get('button').trigger('click');
    expect(wrapper.text()).toContain('done');
    expect(localStorage.getItem('activity-seen:9:1')).toContain('"done":"1"');
    expect(store.getters['backgroundTasks/ordered']).toHaveLength(1);
    await wrapper.get('button').trigger('click');
    expect(wrapper.find('a').exists()).toBe(false);
    expect(wrapper.find('button').exists()).toBe(false);
  });

  it('keeps failed recovery visible and distinguishes empty panel state', async () => {
    store.commit('backgroundTasks/setFailed', true);
    render();
    expect(wrapper.get('button').attributes('aria-label')).toContain(
      'Activity unavailable'
    );
    await wrapper.get('button').trigger('click');
    expect(wrapper.text()).toContain("We couldn't update activity.");
    store.commit('backgroundTasks/setFailed', false);
    await wrapper.get('button').trigger('click');
    expect(wrapper.find('button').exists()).toBe(false);
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
