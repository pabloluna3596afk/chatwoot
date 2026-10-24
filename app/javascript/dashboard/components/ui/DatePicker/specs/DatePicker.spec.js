import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { directive as onClickaway } from 'vue3-click-away';
import { startOfDay, endOfDay, startOfMonth } from 'date-fns';
import DatePicker from '../DatePicker.vue';
import DatePickerButton from '../components/DatePickerButton.vue';
import CalendarWeek from '../components/CalendarWeek.vue';
import CalendarDateRange from '../components/CalendarDateRange.vue';
import CalendarDateInput from '../components/CalendarDateInput.vue';
import CalendarFooter from '../components/CalendarFooter.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { dateRanges, getActiveDateRange } from '../helpers/DatePickerHelper';

const mobile = ref(true);
vi.mock('@vueuse/core', async importOriginal => ({
  ...(await importOriginal()),
  useMediaQuery: () => mobile,
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const referenceDate = new Date(2026, 0, 5, 12);
const initialRange = [new Date(2025, 11, 28), new Date(2026, 0, 3)];
let wrapper;

beforeEach(() => {
  mobile.value = true;
  HTMLDialogElement.prototype.close = function close() {
    this.removeAttribute('open');
  };
  HTMLDialogElement.prototype.showModal = function showModal() {
    this.setAttribute('open', '');
  };
});

afterEach(() => wrapper?.unmount());

describe.each([true, false])('DatePicker mobile=%s', isMobile => {
  beforeEach(async () => {
    mobile.value = isMobile;
    wrapper = mount(DatePicker, {
      attachTo: document.body,
      props: { referenceDate, dateRange: initialRange, rangeType: 'custom' },
      global: {
        stubs: {
          TeleportWithDirection: { template: '<div><slot /></div>' },
          NextButton: false,
        },
        directives: { 'on-clickaway': onClickaway },
      },
    });
    await wrapper.findComponent(DatePickerButton).vm.$emit('open');
    await flushPromises();
  });

  it('keeps both date inputs and renders one mobile calendar or two desktop calendars', () => {
    expect(wrapper.findAllComponents(CalendarDateInput)).toHaveLength(2);
    expect(wrapper.findAllComponents(CalendarWeek)).toHaveLength(
      isMobile ? 1 : 2
    );
    expect(wrapper.findComponent(Dialog).exists()).toBe(isMobile);
    expect(wrapper.find('details').exists()).toBe(isMobile);
    expect(wrapper.find('[class*="w-[55rem]"]').exists()).toBe(!isMobile);
  });

  it.each(dateRanges)(
    'preserves preset $value and only emits on Apply',
    async range => {
      wrapper.findComponent(CalendarDateRange).vm.$emit('setRange', range);
      await flushPromises();
      expect(wrapper.emitted('dateRangeChanged')).toBeUndefined();
      if (isMobile) {
        const apply = wrapper
          .findAll('button')
          .find(button => button.text() === 'DATE_PICKER.APPLY_BUTTON');
        await apply.trigger('click');
      } else {
        wrapper.findComponent(CalendarFooter).vm.$emit('change');
      }
      const { start, end } = getActiveDateRange(range.value, referenceDate);
      expect(wrapper.emitted('dateRangeChanged')).toEqual([
        [[start, end, range.value]],
      ]);
      await flushPromises();
      expect(wrapper.findComponent(CalendarWeek).exists()).toBe(false);
    }
  );

  it('selects a range across months and years without changing payload shape', async () => {
    wrapper
      .findComponent(CalendarWeek)
      .vm.$emit('selectDate', new Date(2025, 11, 30));
    await flushPromises();
    wrapper.findComponent(CalendarWeek).vm.$emit('next');
    await flushPromises();
    expect(
      wrapper.findComponent(CalendarWeek).props('startCurrentDate')
    ).toEqual(startOfMonth(referenceDate));
    wrapper
      .findComponent(CalendarWeek)
      .vm.$emit('selectDate', new Date(2026, 0, 4));
    await flushPromises();
    if (isMobile) {
      await wrapper
        .findAll('button')
        .find(button => button.text() === 'DATE_PICKER.APPLY_BUTTON')
        .trigger('click');
    } else {
      wrapper.findComponent(CalendarFooter).vm.$emit('change');
    }
    expect(wrapper.emitted('dateRangeChanged')).toEqual([
      [[new Date(2025, 11, 30), new Date(2026, 0, 4), 'custom']],
    ]);
  });

  if (!isMobile) {
    it.each(['trigger', 'outside'])(
      'applies the desktop draft once on a click on %s',
      async target => {
        wrapper
          .findComponent(CalendarDateRange)
          .vm.$emit('setRange', dateRanges[1]);
        await flushPromises();
        // The real clickaway directive ignores clicks during its mounting tick.
        await new Promise(resolve => {
          setTimeout(resolve, 0);
        });
        if (target === 'trigger') {
          await wrapper
            .findComponent(DatePickerButton)
            .find('button')
            .trigger('click');
        } else {
          document.body.dispatchEvent(
            new Event(document.ontouchstart !== null ? 'click' : 'touchstart', {
              bubbles: true,
            })
          );
          await flushPromises();
        }
        const { start, end } = getActiveDateRange(
          dateRanges[1].value,
          referenceDate
        );
        expect(wrapper.emitted('dateRangeChanged')).toEqual([
          [[start, end, dateRanges[1].value]],
        ]);
        expect(wrapper.findComponent(CalendarWeek).exists()).toBe(false);
        expect(wrapper.emitted('close')).toBeUndefined();
      }
    );
  }
});

describe('mobile draft', () => {
  beforeEach(async () => {
    wrapper = mount(DatePicker, {
      props: {
        referenceDate,
        dateRange: initialRange,
        rangeType: 'custom',
        hasAppliedRange: false,
      },
      global: {
        stubs: {
          TeleportWithDirection: { template: '<div><slot /></div>' },
          NextButton: false,
        },
        directives: { 'on-clickaway': {} },
      },
    });
    await flushPromises();
  });

  it.each(['cancel', 'dismiss'])(
    'restores applied dates on %s without emitting a filter',
    async action => {
      wrapper
        .findComponent(CalendarDateRange)
        .vm.$emit('setRange', dateRanges[1]);
      await flushPromises();
      if (action === 'cancel') {
        await wrapper
          .findAll('button')
          .find(button => button.text() === 'DIALOG.BUTTONS.CANCEL')
          .trigger('click');
      } else {
        wrapper.findComponent(Dialog).vm.$emit('close');
        await flushPromises();
      }
      expect(wrapper.emitted('dateRangeChanged')).toBeUndefined();
      expect(wrapper.emitted('close')).toHaveLength(1);
      expect(wrapper.findComponent(DatePickerButton).props()).toMatchObject({
        selectedStartDate: startOfDay(initialRange[0]),
        selectedEndDate: endOfDay(initialRange[1]),
        selectedRange: 'custom',
      });
      wrapper.findComponent(DatePickerButton).vm.$emit('open');
      await flushPromises();
      expect(
        wrapper.findComponent(CalendarWeek).props('startCurrentDate')
      ).toEqual(startOfMonth(initialRange[0]));
    }
  );

  it('disables Apply for an incomplete custom range and restarts when the end precedes the start', async () => {
    wrapper
      .findComponent(CalendarWeek)
      .vm.$emit('selectDate', new Date(2026, 0, 4));
    await flushPromises();
    const apply = wrapper
      .findAll('button')
      .find(button => button.text() === 'DATE_PICKER.APPLY_BUTTON');
    expect(apply.attributes('disabled')).toBeDefined();
    wrapper
      .findComponent(CalendarWeek)
      .vm.$emit('selectDate', new Date(2026, 0, 2));
    await flushPromises();
    expect(
      wrapper.findComponent(CalendarWeek).props('selectedStartDate')
    ).toEqual(new Date(2026, 0, 2));
    expect(apply.attributes('disabled')).toBeDefined();
    expect(wrapper.emitted('dateRangeChanged')).toBeUndefined();
  });

  it('keeps manual range validation on Enter inside the modal form', async () => {
    const inputs = wrapper.findAll('input');
    await inputs[0].setValue(
      new Date(2025, 11, 29).toLocaleDateString(navigator.language)
    );
    await inputs[0].trigger('keydown', { key: 'Enter' });
    expect(
      wrapper.findComponent(CalendarWeek).props('selectedStartDate')
    ).toEqual(new Date(2025, 11, 29));
    expect(wrapper.emitted('dateRangeChanged')).toBeUndefined();
  });

  it('folds presets after a selection and uses non-submit buttons throughout the modal', async () => {
    const details = wrapper.find('details');
    details.element.open = true;
    await details.trigger('toggle');
    const presets = wrapper.findComponent(CalendarDateRange).findAll('button');
    await presets[1].trigger('click');
    expect(details.element.open).toBe(false);
    expect(
      wrapper
        .findAll('dialog button')
        .every(button => button.attributes('type') === 'button')
    ).toBe(true);
  });

  it('Clear prepares last seven days and preserves reference-date day boundaries', async () => {
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'DATE_PICKER.CLEAR_BUTTON')
      .trigger('click');
    expect(wrapper.emitted('dateRangeChanged')).toBeUndefined();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'DATE_PICKER.APPLY_BUTTON')
      .trigger('click');
    expect(wrapper.emitted('dateRangeChanged')).toEqual([
      [
        [
          startOfDay(new Date(2025, 11, 30)),
          endOfDay(referenceDate),
          'last7days',
        ],
      ],
    ]);
  });
});
