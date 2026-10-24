import { mount, flushPromises } from '@vue/test-utils';
import DatePicker from '../DatePicker.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import CalendarWeek from '../components/CalendarWeek.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

let wrapper;
const originalShowModal = HTMLDialogElement.prototype.showModal;
const originalClose = HTMLDialogElement.prototype.close;

afterEach(() => {
  wrapper?.unmount();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  HTMLDialogElement.prototype.showModal = originalShowModal;
  HTMLDialogElement.prototype.close = originalClose;
});

it.each([390, 1023, 1024, 1280])(
  'selects the responsive tree at %s px through matchMedia',
  async width => {
    const matchMedia = vi.fn(query => ({
      matches: query === '(max-width: 1023px)' && width <= 1023,
      media: query,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    }));
    vi.stubGlobal('matchMedia', matchMedia);
    HTMLDialogElement.prototype.showModal = function showModal() {
      this.setAttribute('open', '');
    };
    HTMLDialogElement.prototype.close = function close() {
      this.removeAttribute('open');
    };
    wrapper = mount(DatePicker, {
      props: { hasAppliedRange: false },
      global: {
        stubs: {
          TeleportWithDirection: { template: '<div><slot /></div>' },
          NextButton: false,
        },
        directives: { 'on-clickaway': {} },
      },
    });
    await flushPromises();
    expect(matchMedia).toHaveBeenCalledWith('(max-width: 1023px)');
    const mobile = width <= 1023;
    expect(wrapper.findComponent(Dialog).exists()).toBe(mobile);
    expect(wrapper.findAllComponents(CalendarWeek)).toHaveLength(
      mobile ? 1 : 2
    );
    expect(wrapper.find('[class*="w-[55rem]"]').exists()).toBe(!mobile);
    if (mobile) {
      expect(wrapper.find('dialog[open]').classes()).toContain(
        'w-[min(100vw-2rem,24rem)]'
      );
    }
  }
);
