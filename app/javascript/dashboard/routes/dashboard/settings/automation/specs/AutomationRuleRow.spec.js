import { mount } from '@vue/test-utils';
import AutomationRuleRow from '../AutomationRuleRow.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => {
      const translations = {
        'AUTOMATION.TIME_WINDOW.SUMMARY_ALL_DAYS': 'Every day',
        'AUTOMATION.TIME_WINDOW.SUMMARY_WEEKDAYS': 'Mon–Fri',
        'AUTOMATION.TIME_WINDOW.SUMMARY_ROW_IN': `Message time: within ${params?.summary}`,
        'AUTOMATION.TIME_WINDOW.SUMMARY_ROW_OUT': `Message time: outside ${params?.summary}`,
      }[key];
      return translations || key;
    },
  }),
}));

describe('AutomationRuleRow', () => {
  it.each([
    ['equal_to', 'Message time: within 22:00–06:00 · Mon–Fri'],
    ['not_equal_to', 'Message time: outside 22:00–06:00 · Mon–Fri'],
  ])('shows the %s condition with its correct meaning', (operator, summary) => {
    const wrapper = mount(AutomationRuleRow, {
      props: {
        automation: {
          active: true,
          name: 'Night shift',
          description: 'Handle night messages',
          created_on: '2026-11-26T12:00:00Z',
          conditions: [
            {
              attribute_key: 'message_time_window',
              filter_operator: operator,
              values: ['22:00-06:00|mon,tue,wed,thu,fri'],
            },
          ],
        },
      },
      global: {
        mocks: {
          $t: (key, params) => {
            if (key === 'AUTOMATION.TIME_WINDOW.SUMMARY_ROW_IN') {
              return `Message time: within ${params.summary}`;
            }
            if (key === 'AUTOMATION.TIME_WINDOW.SUMMARY_ROW_OUT') {
              return `Message time: outside ${params.summary}`;
            }
            return key;
          },
        },
        stubs: {
          BaseTableRow: { template: '<div><slot /></div>' },
          BaseTableCell: { template: '<div><slot /></div>' },
          Button: true,
          ToggleSwitch: true,
        },
      },
    });

    expect(wrapper.text()).toContain(summary);
    expect(wrapper.text()).not.toContain('message_time_window');
  });
});
