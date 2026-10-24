import { computed } from 'vue';
import { shallowMount, flushPromises } from '@vue/test-utils';
import { startOfDay, endOfDay } from 'date-fns';
import DatePicker from '../DatePicker.vue';
import ReportFilters from 'dashboard/routes/dashboard/settings/reports/components/ReportFilters.vue';
import OverviewReportFilters from 'dashboard/routes/dashboard/settings/reports/components/OverviewReportFilters.vue';
import CsatFilters from 'dashboard/routes/dashboard/settings/reports/components/Csat/CsatFilters.vue';
import SLAReportFilters from 'dashboard/routes/dashboard/settings/reports/components/SLA/SLAReportFilters.vue';
import AuditLogFilters from 'dashboard/routes/dashboard/settings/auditlogs/components/AuditLogFilters.vue';
import PanelShow from 'dashboard/routes/dashboard/settings/reports/panels/Show.vue';
import SavedReportPanelsAPI from 'dashboard/api/savedReportPanels';
import { panelPickerRangeToUnix } from 'dashboard/routes/dashboard/settings/reports/panels/panelConstants';

const mocks = vi.hoisted(() => ({ replace: vi.fn(), dispatch: vi.fn() }));
vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRoute: () => ({ params: { id: '42' }, query: {} }),
  useRouter: () => ({ replace: mocks.replace }),
}));
vi.mock('vuex', async importOriginal => ({
  ...(await importOriginal()),
  useStore: () => ({ getters: {} }),
}));
vi.mock(
  'dashboard/routes/dashboard/settings/reports/components/ReportHeader.vue',
  () => ({ default: { template: '<header><slot /></header>' } })
);
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: mocks.dispatch }),
  useMapGetter: () => computed(() => []),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: computed(() => ({})),
    accountScopedRoute: vi.fn(),
    isCloudFeatureEnabled: () => false,
  }),
}));
vi.mock('dashboard/api/savedReportPanels', () => ({
  default: { show: vi.fn(), run: vi.fn() },
}));

const dates = [new Date(2025, 11, 30), new Date(2026, 0, 4)];
let wrapper;
afterEach(() => wrapper?.unmount());

describe('date range consumer contracts', () => {
  it.each([
    ReportFilters,
    OverviewReportFilters,
    CsatFilters,
    SLAReportFilters,
  ])(
    'keeps report day boundaries, range type and URL parameters for $.__name',
    async component => {
      wrapper = shallowMount(component);
      await flushPromises();
      const picker = wrapper.findComponent(DatePicker);
      picker.vm.$emit('dateRangeChanged', [...dates, 'custom']);
      await flushPromises();
      expect(wrapper.emitted('filterChange').at(-1)[0]).toMatchObject({
        from: startOfDay(dates[0]).getTime() / 1000,
        to: Math.floor(endOfDay(dates[1]).getTime() / 1000),
      });
      expect(picker.props('dateRange')).toEqual(dates);
      expect(picker.props('rangeType')).toBe('custom');
      expect(mocks.replace).toHaveBeenLastCalledWith({
        query: expect.objectContaining({ range: 'custom' }),
      });
    }
  );

  it('keeps audit since/until in seconds and never applies on close', async () => {
    wrapper = shallowMount(AuditLogFilters, {
      props: { since: 100, until: 200 },
    });
    const picker = wrapper.findComponent(DatePicker);
    picker.vm.$emit('close');
    expect(wrapper.emitted('update')).toBeUndefined();
    picker.vm.$emit('dateRangeChanged', [...dates, 'custom']);
    expect(wrapper.emitted('update')).toEqual([
      [
        {
          range: 'custom',
          since: startOfDay(dates[0]).getTime() / 1000,
          until: Math.floor(endOfDay(dates[1]).getTime() / 1000),
        },
      ],
    ]);
  });

  it('keeps the saved panel reporting timezone when running an override', async () => {
    SavedReportPanelsAPI.show.mockResolvedValue({
      data: {
        name: 'Panel',
        date_preset: 'last_7_days',
        reporting_timezone: 'America/Guayaquil',
        widgets: [],
      },
    });
    SavedReportPanelsAPI.run.mockResolvedValue({ data: { widgets: [] } });
    wrapper = shallowMount(PanelShow);
    await flushPromises();
    const picker = wrapper.findComponent(DatePicker);
    picker.vm.$emit('dateRangeChanged', [...dates, 'custom']);
    await flushPromises();
    const [since, until] = panelPickerRangeToUnix(dates, 'America/Guayaquil');
    expect(SavedReportPanelsAPI.run).toHaveBeenLastCalledWith('42', {
      since,
      until,
      timezone_offset: -new Date().getTimezoneOffset() / 60,
    });
    expect(picker.props('dateRange')).toEqual(dates);
    expect(picker.props('rangeType')).toBe('custom');
  });
});
