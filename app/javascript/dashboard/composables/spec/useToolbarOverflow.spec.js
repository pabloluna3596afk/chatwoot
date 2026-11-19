import { defineComponent, nextTick, ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { useToolbarOverflow } from '../useToolbarOverflow';

const KEYS = [
  'attach',
  'template',
  'audio',
  'emoji',
  'contact',
  'video',
  'quoted',
  'canned',
  'article',
  'signature',
];

describe('useToolbarOverflow', () => {
  let callback;
  let wrapper;
  let disconnect;
  beforeEach(() => {
    disconnect = vi.fn();
    vi.stubGlobal(
      'ResizeObserver',
      class {
        constructor(fn) {
          callback = fn;
          this.observe = vi.fn();
          this.disconnect = disconnect;
        }
      }
    );
    vi.spyOn(HTMLElement.prototype, 'offsetWidth', 'get').mockImplementation(
      function width() {
        return this.dataset.toolbarItem ? 32 : 0;
      }
    );
    wrapper = mount(
      defineComponent({
        setup() {
          const container = ref(null);
          const items = ref(
            KEYS.map((key, index) => ({ key, hideRank: 10 - index }))
          );
          return { container, items, ...useToolbarOverflow(container, items) };
        },
        template:
          '<div ref="container"><span v-for="item in items" :key="item.key" :data-toolbar-item="item.key" v-show="!hiddenKeys.includes(item.key)"><button>{{ item.key }}</button></span></div>',
      })
    );
  });
  afterEach(() => {
    wrapper.unmount();
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  // Available width excludes Send. Ten 32px buttons + nine 8px gaps = 392px.
  it.each([
    [400, 0],
    [330, 3],
    [290, 4],
    [250, 5],
    [120, 8],
  ])('fits measured buttons into %s px', async (width, hiddenCount) => {
    await flushPromises();
    callback([{ contentRect: { width } }]);
    await flushPromises();
    expect(wrapper.vm.hiddenKeys).toEqual(
      [...KEYS].reverse().slice(0, hiddenCount)
    );
    expect(wrapper.vm.hiddenItems.map(item => item.key)).toEqual(
      KEYS.slice(KEYS.length - hiddenCount).filter(() => hiddenCount)
    );
    expect(wrapper.findAll('button')).toHaveLength(10);
    expect(wrapper.find('[data-toolbar-item="attach"]').isVisible()).toBe(true);
  });

  it('uses ranks rather than DOM order and remeasures newly eligible buttons', async () => {
    wrapper.vm.items = [...wrapper.vm.items].reverse();
    await nextTick();
    callback([{ contentRect: { width: 330 } }]);
    await flushPromises();
    expect(wrapper.vm.hiddenKeys).toEqual(['signature', 'article', 'canned']);
    wrapper.vm.items = wrapper.vm.items.filter(
      item => item.key !== 'signature'
    );
    await flushPromises();
    expect(wrapper.vm.hiddenKeys).toEqual(['article', 'canned']);
    callback([{ contentRect: { width: 400 } }]);
    await flushPromises();
    expect(wrapper.vm.hiddenItems).toEqual([]);
  });

  it('disconnects on unmount', () => {
    wrapper.unmount();
    expect(disconnect).toHaveBeenCalled();
  });
});
