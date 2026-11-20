import { defineComponent, ref, nextTick } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { useActivityTime } from '../useActivityTime';

describe('shared activity clock', () => {
  const wrappers = [];
  const render = (age, locale = 'es') => {
    const wrapper = mount(
      defineComponent({
        setup() {
          return useActivityTime(ref(Date.now() / 1000 - age));
        },
        template:
          '<time :datetime="isoTime" :title="exactTime">{{ relativeTime }}</time>',
      }),
      {
        global: {
          plugins: [createI18n({ legacy: false, locale, messages: {} })],
        },
      }
    );
    wrappers.push(wrapper);
    return wrapper;
  };
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-11-20T18:00:00Z'));
  });
  afterEach(() => {
    wrappers.splice(0).forEach(wrapper => wrapper.unmount());
    vi.useRealTimers();
  });

  it('truncates minutes and hours and supplies ISO and exact time', () => {
    expect(render(25 * 60 + 59).text()).toMatch(/25/);
    const wrapper = render(3 * 3600 + 3599);
    expect(wrapper.text()).toMatch(/3/);
    expect(wrapper.text()).not.toMatch(/4/);
    expect(wrapper.get('time').attributes('datetime')).toBe(
      '2026-11-20T14:00:01.000Z'
    );
    expect(wrapper.get('time').attributes('title')).toContain('2026');
  });

  it('accepts dashboard locales with underscores through the shared locale resolver', () => {
    const wrapper = render(25 * 60, 'pt_BR');
    expect(wrapper.text()).toContain('25');
    expect(wrapper.get('time').attributes('title')).toContain('2026');
  });

  it('uses one interval across activities and disposes it with the last consumer', async () => {
    const first = render(60);
    const count = vi.getTimerCount();
    const second = render(60, 'en');
    expect(vi.getTimerCount()).toBe(count);
    await vi.advanceTimersByTimeAsync(60_000);
    expect(first.text()).toContain('2');
    expect(second.text()).toContain('2');
    first.unmount();
    expect(vi.getTimerCount()).toBe(count);
    second.unmount();
    expect(vi.getTimerCount()).toBe(0);
  });

  it('refreshes immediately when returning to a visible tab', async () => {
    const wrapper = render(60);
    vi.setSystemTime(new Date('2026-11-20T18:24:00Z'));
    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      value: 'visible',
    });
    document.dispatchEvent(new Event('visibilitychange'));
    await nextTick();
    expect(wrapper.text()).toContain('25');
  });
});
