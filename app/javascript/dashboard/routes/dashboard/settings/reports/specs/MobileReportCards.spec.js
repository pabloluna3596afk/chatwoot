import { defineComponent, ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import reportMessages from 'dashboard/i18n/locale/en/report.json';
import settingsMessages from 'dashboard/i18n/locale/en/settings.json';
import slaMessages from 'dashboard/i18n/locale/en/sla.json';
import AgentTable from '../components/overview/AgentTable.vue';
import TeamTable from '../components/overview/TeamTable.vue';
import SummaryReports from '../components/SummaryReports.vue';
import CsatTable from '../components/CsatTable.vue';
import SLATable from '../components/SLA/SLATable.vue';
import PanelsIndex from '../panels/Index.vue';

const reportState = vi.hoisted(() => ({
  rows: [],
  metrics: [],
  csatResponses: [],
  csatMetrics: { totalResponseCount: 1 },
  panelRows: [],
  panelGet: vi.fn(),
  push: vi.fn(),
}));

vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings: { value: {} },
    updateUISettings: vi.fn(),
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key => {
    const getter = Array.isArray(key) ? key[0] : key;
    if (getter === 'csat/getCSATResponses')
      return ref(reportState.csatResponses);
    if (getter === 'csat/getMetrics') return ref(reportState.csatMetrics);
    if (getter === 'csat/getUIFlags') return ref({ isFetching: false });
    if (getter === 'summaryReports/getUIFlags') return ref({});
    if (getter === 'rows') return ref(reportState.rows);
    if (getter === 'metrics') return ref(reportState.metrics);
    return ref([]);
  },
  useStore: () => ({ dispatch: vi.fn().mockResolvedValue(undefined) }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: () => false,
    isOnChatwootCloud: { value: false },
    currentAccount: { value: { name: 'InboxHub' } },
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));
vi.mock('dashboard/composables/useStatusLabel', () => ({
  useStatusLabel: () => ({
    getResolutionCountLabel: () => 'Resolved conversations',
  }),
}));
vi.mock('shared/composables/useLocale', () => ({
  useLocale: () => ({ resolvedLocale: ref('en') }),
}));
vi.mock('dashboard/api/savedReportPanels', () => ({
  default: { get: (...args) => reportState.panelGet(...args), update: vi.fn() },
}));
vi.mock('vue-router', async importOriginal => {
  const actual = await importOriginal();
  return { ...actual, useRouter: () => ({ push: reportState.push }) };
});

const CardStub = defineComponent({
  inheritAttrs: false,
  template:
    '<article class="report-card"><h3><slot name="title">{{ $attrs.title }}</slot></h3><p>{{ $attrs.subtitle }}</p><div><slot name="chips" /></div><slot name="after" /></article>',
});
const ChipStub = defineComponent({ template: '<span><slot /></span>' });
const i18n = createI18n({
  legacy: false,
  locale: 'en',
  fallbackLocale: 'en',
  messages: {
    en: {
      ...reportMessages,
      ...settingsMessages,
      ...slaMessages,
      CONVERSATION: { HEADER: { MORE_ACTIONS: 'More actions' } },
      SETTINGS: {
        SORT_BY: 'Sort by',
      },
      COMPONENTS: {
        SHOW_MORE_BLOCK: { SHOW_MORE: 'Show more', SHOW_LESS: 'Show less' },
      },
      REPORT_PANELS: {
        HEADER: 'Reports',
        DESCRIPTION: 'Saved reports',
        CREATE: 'Create report',
        EMPTY: 'No reports',
        FAVORITE: 'Favorite',
        EDIT: 'Edit',
        OPEN: 'Open',
        LOADING: 'Loading',
        DATE_PRESETS: { LAST_7_DAYS: 'Last 7 days' },
        LIST: {
          SCOPE_HINT: 'Report scope',
          COLUMNS: {
            NAME: 'Name',
            PERIOD: 'Period',
            WIDGETS: 'Widgets',
            FILTERS: 'Filters',
            UPDATED: 'Updated',
            ACTIONS: 'Actions',
          },
        },
        ERRORS: { LOAD: 'Load failed', SAVE: 'Save failed' },
      },
      SUMMARY_REPORTS: { ...reportMessages.SUMMARY_REPORTS },
    },
  },
});
const stubs = {
  ListCard: CardStub,
  InfoChip: ChipStub,
  Table: true,
  Pagination: true,
  Avatar: true,
  Spinner: true,
  EmptyState: true,
  OverviewReportFilters: true,
  SummaryReportLink: {
    props: ['row'],
    template: '<a>{{ row.original.name }}</a>',
  },
  ReportHeader: true,
  Button: true,
  CsatTableLoader: true,
  CsatContactCell: true,
  CsatExpandedRow: true,
  CsatEmptyState: true,
  ShowMore: { props: ['text'], template: '<span>{{ text }}</span>' },
  UserAvatarWithName: true,
  TableFooter: true,
  TableHeaderCell: true,
  SLAReportItem: true,
  CardLabels: true,
  SLAViewDetails: true,
  'router-link': { template: '<a><slot /></a>' },
};
const mountReport = (component, props = {}) =>
  mount(component, {
    props,
    global: {
      plugins: [i18n],
      stubs,
      mocks: {
        $t: key => key,
        $route: { params: { accountId: 1 }, query: {} },
      },
    },
  });

describe('report table mobile cards preserve the rendered metrics', () => {
  beforeEach(() => {
    reportState.rows = [];
    reportState.metrics = [];
    reportState.csatResponses = [];
    reportState.panelRows = [];
    vi.clearAllMocks();
  });

  it('renders agent and team rows with their same count values and keeps desktop tables', () => {
    const agents = mountReport(AgentTable, {
      agents: [{ id: 1, name: 'Ana García', email: 'ana@example.com' }],
      agentMetrics: [{ assignee_id: 1, open: 12, unattended: 3 }],
    });
    expect(agents.find('.report-card').text()).toContain('12');
    expect(agents.find('.report-card').text()).toContain('3');
    expect(agents.find('[class~="md:block"]').exists()).toBe(true);

    const teams = mountReport(TeamTable, {
      teams: [{ id: 2, name: 'Soporte' }],
      teamMetrics: [{ team_id: 2, open: 8, unattended: 2 }],
    });
    expect(teams.find('.report-card').text()).toContain('8');
    expect(teams.find('.report-card').text()).toContain('2');
    expect(teams.find('[class~="md:block"]').exists()).toBe(true);
  });

  it('renders all summary metrics in their existing formatted units and keeps the report link', async () => {
    reportState.rows = [{ id: 3, name: 'WhatsApp' }];
    reportState.metrics = [
      {
        id: 3,
        conversationsCount: 12,
        avgFirstResponseTime: 60,
        avgResolutionTime: 120,
        avgReplyTime: 30,
        resolvedConversationsCount: 5,
      },
    ];
    const wrapper = mountReport(SummaryReports, {
      type: 'inbox',
      getterKey: 'rows',
      summaryKey: 'metrics',
      actionKey: 'fetchSummary',
      fetchItemsKey: 'fetchRows',
    });
    await flushPromises();
    const card = wrapper.find('.report-card');
    expect(card.text()).toContain('WhatsApp');
    expect(card.text()).toContain('12');
    expect(card.text()).toContain('5');
    expect(card.text()).toContain('1 Min');
    expect(card.text()).toContain('2 Min');
    expect(card.text()).toContain('30 Sec');
    expect(wrapper.find('#summary-report-sort').exists()).toBe(true);
  });

  it('renders CSAT contact, rating, feedback, agent, and preserves expansion affordance', () => {
    reportState.csatResponses = [
      {
        id: 7,
        contact: { name: 'Luis' },
        assigned_agent: { name: 'Ana' },
        rating: 5,
        feedback_message: 'Muy bien',
        conversation_id: 22,
        created_at: Math.floor(Date.now() / 1000),
      },
    ];
    const wrapper = mountReport(CsatTable);
    const card = wrapper.find('.report-card');
    expect(card.text()).toContain('Luis');
    expect(card.text()).toContain('Muy bien');
    expect(card.text()).toContain('Ana');
    expect(wrapper.find('[class~="md:block"]').exists()).toBe(true);
  });

  it('renders SLA conversation, policy, agent, labels, and detail action', () => {
    const wrapper = mountReport(SLATable, {
      slaReports: [
        {
          applied_sla: { id: 5, sla_name: 'Priority' },
          conversation: {
            id: 44,
            contact: { name: 'Nora' },
            assignee: { name: 'Ana' },
            labels: 'urgent, billing',
          },
          sla_events: [{ id: 1 }],
        },
      ],
    });
    expect(wrapper.find('.report-card').text()).toContain('#44 Nora');
    expect(wrapper.find('.report-card').text()).toContain('Priority');
    expect(wrapper.find('.report-card').text()).toContain('Ana');
    expect(wrapper.find('[class~="md:block"]').exists()).toBe(true);
  });

  it('renders saved report metadata and keeps favorite, edit, and open actions', async () => {
    reportState.panelGet.mockResolvedValue({
      data: [
        {
          id: 9,
          name: 'Operación',
          description: 'Canal de soporte',
          date_preset: 'last_7_days',
          widgets: [{}, {}],
          filters: [{}],
          updated_at: 1792886400,
          favorite: true,
        },
      ],
    });
    const wrapper = mountReport(PanelsIndex);
    await flushPromises();
    const card = wrapper.find('.report-card');
    expect(card.text()).toContain('Operación');
    expect(card.text()).toContain('2');
    expect(card.text()).toContain('1');
    expect(card.text()).toContain('Favorite');
    expect(card.findAll('button')).toHaveLength(1);
    expect(wrapper.find('[class~="md:block"]').exists()).toBe(true);
  });
});
