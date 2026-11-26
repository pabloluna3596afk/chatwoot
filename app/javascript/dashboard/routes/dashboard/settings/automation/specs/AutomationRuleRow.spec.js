import { mount } from '@vue/test-utils';
import AutomationRuleRow from '../AutomationRuleRow.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key =>
      ({
        'AUTOMATION.TIME_WINDOW.SUMMARY_ALL_DAYS': 'Every day',
        'AUTOMATION.TIME_WINDOW.SUMMARY_WEEKDAYS': 'Mon–Fri',
      })[key] || key,
  }),
}));

describe('AutomationRuleRow', () => {
  it('shows the message time condition as readable text', () => {
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
              values: ['22:00-06:00|mon,tue,wed,thu,fri'],
            },
          ],
        },
      },
      global: {
        mocks: {
          $t: (key, params) =>
            key === 'AUTOMATION.TIME_WINDOW.SUMMARY_ROW'
              ? `Message time: ${params.summary}`
              : key,
        },
        stubs: {
          BaseTableRow: { template: '<div><slot /></div>' },
          BaseTableCell: { template: '<div><slot /></div>' },
          Button: true,
          ToggleSwitch: true,
        },
      },
    });

    expect(wrapper.text()).toContain('Message time: 22:00–06:00 · Mon–Fri');
    expect(wrapper.text()).not.toContain('message_time_window');
  });
});
