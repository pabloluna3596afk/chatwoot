import { computed, defineComponent } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import Edit from '../Edit.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ConditionRow from 'dashboard/components-next/filter/ConditionRow.vue';
import SavedReportPanelsAPI from 'dashboard/api/savedReportPanels';
import esReports from 'dashboard/i18n/locale/es/report.json';
import { PREVIEW_DEBOUNCE_MS } from '../panelConstants';

const mocks = vi.hoisted(() => ({
  dispatch: vi.fn(),
  push: vi.fn(),
  replace: vi.fn(),
  alert: vi.fn(),
  conversationAttributes: [],
}));
vi.mock('../../components/ReportHeader.vue', () => ({
  default: { template: '<header><slot /></header>' },
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { id: '42', accountId: '1' } }),
  useRouter: () => ({ push: mocks.push, replace: mocks.replace }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: mocks.dispatch }),
  useMapGetter: key =>
    computed(() =>
      key === 'attributes/getConversationAttributes'
        ? mocks.conversationAttributes
        : []
    ),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: computed(() => ({
      reporting_timezone: 'America/Guayaquil',
    })),
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: mocks.alert }));
vi.mock('dashboard/components-next/filter/provider', () => ({
  useConversationFilterContext: () => ({
    filterTypes: computed(() => [{ attributeKey: 'status', value: 'status' }]),
  }),
}));
vi.mock('dashboard/components-next/filter/operators', () => ({
  useOperators: () => ({
    presenceOperators: computed(() => []),
    getOperatorTypes: () => [],
  }),
}));
vi.mock('dashboard/api/savedReportPanels', () => ({
  default: {
    show: vi.fn(),
    preview: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    delete: vi.fn(),
  },
}));

const conditionStub = defineComponent({
  /* eslint-disable vue/no-unused-properties, vue/no-unused-emit-declarations -- models are changed through vm.$emit in these tests */
  props: {
    attributeKey: { type: String, default: '' },
    filterOperator: { type: String, default: '' },
    values: { type: [String, Object, Array], default: () => [] },
    queryOperator: { type: String, default: '' },
  },
  emits: ['update:values', 'update:queryOperator', 'remove'],
  setup(_props, { expose }) {
    expose({ validate: () => true });
  },
  template: '<li />',
  /* eslint-enable vue/no-unused-properties, vue/no-unused-emit-declarations */
});
let wrapper;
const mountEditor = (isNew = true) =>
  mount(Edit, {
    props: { isNew },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'es',
          missingWarn: false,
          fallbackWarn: false,
          messages: { es: esReports },
        }),
      ],
      stubs: {
        ConditionRow: conditionStub,
        PanelWidgetCard: {
          props: ['widget', 'result'],
          template: '<div data-testid="preview-card">{{ result?.value }}</div>',
        },
      },
    },
  });
const picker = id =>
  wrapper
    .findAllComponents(ComboBox)
    .find(box => box.attributes('data-testid') === id);

describe('guided panel editor', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    mocks.conversationAttributes = [];
    mocks.dispatch.mockResolvedValue(undefined);
    SavedReportPanelsAPI.preview.mockImplementation(params =>
      Promise.resolve({
        data: {
          widgets: params.saved_report_panel.widgets.map(widget => ({
            id: widget.id,
            value: 7,
          })),
        },
      })
    );
    SavedReportPanelsAPI.create.mockResolvedValue({ data: { id: 99 } });
    SavedReportPanelsAPI.update.mockResolvedValue({});
  });
  afterEach(() => {
    wrapper?.unmount();
    vi.useRealTimers();
  });

  it('navigates business steps, chooses a chart and groups by month with existing menus', async () => {
    wrapper = mountEditor();
    await flushPromises();
    expect(wrapper.find('nav').text()).toContain('Qué quieres ver');
    expect(wrapper.find('[data-testid="choose-step"]').isVisible()).toBe(true);
    await wrapper.find('[data-testid="type-chart"]').trigger('click');
    await wrapper.find('[data-testid="next-step"]').trigger('click');
    expect(wrapper.find('[data-testid="group-step"]').isVisible()).toBe(true);
    picker('chart-group').vm.$emit('update:modelValue', 'month');
    await wrapper.find('[data-testid="next-step"]').trigger('click');
    expect(wrapper.find('[data-testid="filters-step"]').isVisible()).toBe(true);
    await wrapper.find('[data-testid="next-step"]').trigger('click');
    expect(wrapper.find('[data-testid="preview-step"]').isVisible()).toBe(true);
    expect(wrapper.find('[data-testid="save-panel"]').exists()).toBe(true);
    expect(wrapper.find('select').exists()).toBe(false);
    await vi.advanceTimersByTimeAsync(PREVIEW_DEBOUNCE_MS);
    expect(
      SavedReportPanelsAPI.preview.mock.lastCall[0].saved_report_panel
        .widgets[0]
    ).toMatchObject({ type: 'chart', group_by: 'month' });
    await wrapper.find('[data-testid="previous-step"]').trigger('click');
    expect(wrapper.find('[data-testid="filters-step"]').isVisible()).toBe(true);
    expect(SavedReportPanelsAPI.create).not.toHaveBeenCalled();
  });

  it('debounces changes for 600 ms and previews without requiring a name or saving', async () => {
    wrapper = mountEditor();
    await flushPromises();
    await vi.advanceTimersByTimeAsync(PREVIEW_DEBOUNCE_MS - 1);
    expect(SavedReportPanelsAPI.preview).not.toHaveBeenCalled();
    picker('metric-picker').vm.$emit('update:modelValue', 'resolutions_count');
    await flushPromises();
    await vi.advanceTimersByTimeAsync(300);
    picker('metric-picker').vm.$emit(
      'update:modelValue',
      'avg_first_response_time'
    );
    await flushPromises();
    await vi.advanceTimersByTimeAsync(PREVIEW_DEBOUNCE_MS);
    expect(SavedReportPanelsAPI.preview).toHaveBeenCalledTimes(1);
    expect(
      SavedReportPanelsAPI.preview.mock.lastCall[0].saved_report_panel
    ).toMatchObject({
      name: '',
      widgets: [{ metric: 'avg_first_response_time' }],
    });
    expect(wrapper.find('[data-testid="preview-card"]').text()).toBe('7');
    expect(SavedReportPanelsAPI.create).not.toHaveBeenCalled();
    expect(SavedReportPanelsAPI.update).not.toHaveBeenCalled();
  });

  it('waits for valid filters and sends their values while another step is visible', async () => {
    wrapper = mountEditor();
    await flushPromises();
    await wrapper.find('[data-testid="step-2"]').trigger('click');
    await wrapper.find('[data-testid="add-filter"]').trigger('click');
    await vi.advanceTimersByTimeAsync(PREVIEW_DEBOUNCE_MS);
    expect(SavedReportPanelsAPI.preview).not.toHaveBeenCalled();
    wrapper
      .findComponent(ConditionRow)
      .vm.$emit('update:values', { id: 'open', name: 'Open' });
    await wrapper.find('[data-testid="step-0"]').trigger('click');
    await vi.advanceTimersByTimeAsync(PREVIEW_DEBOUNCE_MS);
    expect(
      SavedReportPanelsAPI.preview.mock.lastCall[0].saved_report_panel
        .filters[0]
    ).toMatchObject({ attribute_key: 'status', values: ['open'] });
  });

  it('aborts superseded requests and never replaces the newest preview with an old result', async () => {
    let resolveOld;
    SavedReportPanelsAPI.preview.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOld = resolve;
        })
    );
    wrapper = mountEditor();
    await flushPromises();
    await vi.advanceTimersByTimeAsync(PREVIEW_DEBOUNCE_MS);
    const oldSignal = SavedReportPanelsAPI.preview.mock.lastCall[1].signal;
    const oldId =
      SavedReportPanelsAPI.preview.mock.lastCall[0].saved_report_panel
        .widgets[0].id;
    picker('metric-picker').vm.$emit('update:modelValue', 'resolutions_count');
    await flushPromises();
    expect(oldSignal.aborted).toBe(true);
    await vi.advanceTimersByTimeAsync(PREVIEW_DEBOUNCE_MS);
    resolveOld({ data: { widgets: [{ id: oldId, value: 999 }] } });
    await flushPromises();
    expect(wrapper.find('[data-testid="preview-card"]').text()).toBe('7');
  });

  it('loads an existing panel before previewing and updates only on the bottom button', async () => {
    let resolvePanel;
    SavedReportPanelsAPI.show.mockImplementation(
      () =>
        new Promise(resolve => {
          resolvePanel = resolve;
        })
    );
    wrapper = mountEditor(false);
    await flushPromises();
    await vi.advanceTimersByTimeAsync(PREVIEW_DEBOUNCE_MS);
    expect(SavedReportPanelsAPI.preview).not.toHaveBeenCalled();
    resolvePanel({
      data: {
        name: 'Ventas',
        description: '',
        date_preset: 'last_30_days',
        filters: [],
        widgets: [
          {
            id: 'old',
            type: 'chart',
            metric: 'conversations_count',
            group_by: 'week',
          },
        ],
      },
    });
    await flushPromises();
    await vi.advanceTimersByTimeAsync(PREVIEW_DEBOUNCE_MS);
    expect(
      SavedReportPanelsAPI.preview.mock.lastCall[0].saved_report_panel
        .widgets[0]
    ).toMatchObject({ id: 'old', group_by: 'week' });
    expect(SavedReportPanelsAPI.update).not.toHaveBeenCalled();
    await wrapper.find('[data-testid="step-3"]').trigger('click');
    await wrapper.find('[data-testid="save-panel"]').trigger('click');
    await flushPromises();
    expect(SavedReportPanelsAPI.update).toHaveBeenCalledWith(
      '42',
      expect.objectContaining({
        saved_report_panel: expect.objectContaining({ name: 'Ventas' }),
      })
    );
    expect(mocks.push).toHaveBeenCalledWith({
      name: 'report_panels_show',
      params: { id: '42' },
    });
  });

  it('shows preview errors without creating a record and allows retry on the next change', async () => {
    SavedReportPanelsAPI.preview.mockRejectedValueOnce(new Error('offline'));
    wrapper = mountEditor();
    await flushPromises();
    await vi.advanceTimersByTimeAsync(PREVIEW_DEBOUNCE_MS);
    expect(wrapper.find('[data-testid="live-preview"]').text()).toContain(
      'No se pudo calcular'
    );
    picker('metric-picker').vm.$emit('update:modelValue', 'resolutions_count');
    await flushPromises();
    await vi.advanceTimersByTimeAsync(PREVIEW_DEBOUNCE_MS);
    expect(wrapper.find('[data-testid="preview-card"]').text()).toBe('7');
    expect(SavedReportPanelsAPI.create).not.toHaveBeenCalled();
  });

  it('cancels a queued preview when leaving the editor', async () => {
    wrapper = mountEditor();
    await flushPromises();
    wrapper.unmount();
    await vi.advanceTimersByTimeAsync(PREVIEW_DEBOUNCE_MS);
    expect(SavedReportPanelsAPI.preview).not.toHaveBeenCalled();
    wrapper = null;
  });

  it('previews custom calendar dates in the account timezone and waits when a date is cleared', async () => {
    wrapper = mountEditor();
    await flushPromises();
    await wrapper.find('[data-testid="step-2"]').trigger('click');
    picker('date-preset').vm.$emit('update:modelValue', 'custom');
    await flushPromises();
    const dates = wrapper
      .findAllComponents(Input)
      .filter(input => input.props('type') === 'date');
    dates[0].vm.$emit('update:modelValue', '2026-10-01');
    dates[1].vm.$emit('update:modelValue', '2026-10-07');
    await flushPromises();
    await vi.advanceTimersByTimeAsync(PREVIEW_DEBOUNCE_MS);
    expect(
      SavedReportPanelsAPI.preview.mock.lastCall[0].saved_report_panel
    ).toMatchObject({
      date_preset: 'custom',
      custom_since: Date.parse('2026-10-01T05:00:00Z') / 1000,
      custom_until: Date.parse('2026-10-08T04:59:59Z') / 1000,
    });
    dates[1].vm.$emit('update:modelValue', '');
    await flushPromises();
    await vi.advanceTimersByTimeAsync(PREVIEW_DEBOUNCE_MS);
    expect(SavedReportPanelsAPI.preview).toHaveBeenCalledTimes(1);
  });

  it('keeps the name required for saving even though it is optional for preview', async () => {
    wrapper = mountEditor();
    await flushPromises();
    await wrapper.find('[data-testid="save-panel"]').trigger('click');
    expect(SavedReportPanelsAPI.create).not.toHaveBeenCalled();
    wrapper.findAllComponents(Input)[0].vm.$emit('update:modelValue', 'Ventas');
    await flushPromises();
    await wrapper.find('[data-testid="step-3"]').trigger('click');
    await wrapper.find('[data-testid="save-panel"]').trigger('click');
    await flushPromises();
    expect(SavedReportPanelsAPI.create).toHaveBeenCalledTimes(1);
  });

  it('preserves the chosen custom measure and totals when grouping a table by another entity', async () => {
    mocks.conversationAttributes = [
      {
        attribute_key: 'importe',
        attribute_display_name: 'Importe',
        attribute_display_type: 'currency',
      },
    ];
    SavedReportPanelsAPI.show.mockResolvedValue({
      data: {
        name: 'Ventas',
        date_preset: 'last_7_days',
        filters: [],
        widgets: [
          {
            id: 'sales',
            type: 'table',
            table_kind: 'pivot',
            columns: ['rank', 'name', 'ca:importe__sum'],
            column_aggregations: { 'ca:importe__sum': 'sum' },
            pivot: { row_attribute: 'agent' },
          },
        ],
      },
    });
    wrapper = mountEditor(false);
    await flushPromises();
    await wrapper.find('[data-testid="step-1"]').trigger('click');
    wrapper
      .findAllComponents(ComboBox)
      .find(box => box.attributes('data-testid') === 'pivot-rows')
      .vm.$emit('update:modelValue', 'team');
    await flushPromises();
    await vi.advanceTimersByTimeAsync(PREVIEW_DEBOUNCE_MS);
    expect(
      SavedReportPanelsAPI.preview.mock.lastCall[0].saved_report_panel
        .widgets[0]
    ).toMatchObject({
      table_kind: 'pivot',
      pivot: { row_attribute: 'team' },
      columns: ['rank', 'name', 'ca:importe__sum'],
      column_aggregations: { 'ca:importe__sum': 'sum' },
    });
    expect(SavedReportPanelsAPI.update).not.toHaveBeenCalled();
  });

  it.each([
    { row_attribute: 'created_at', row_granularity: 'month' },
    { row_attribute: 'ca:importe' },
  ])(
    'reopens, previews and saves rows without crossed columns: %o',
    async pivot => {
      mocks.conversationAttributes = [
        {
          attribute_key: 'importe',
          attribute_display_name: 'Importe',
          attribute_display_type: 'currency',
        },
      ];
      const widget = {
        id: 'dynamic',
        type: 'table',
        table_kind: 'pivot',
        columns: ['rank', 'name', 'ca:importe__sum'],
        pivot: {
          ...pivot,
          column_attribute: '',
          column_values: [],
          show_row_totals: true,
        },
        sort: { column: 'ca:importe__sum', direction: 'asc' },
        top_n: { limit: 10, column: 'ca:importe__sum', include_others: true },
        measure_display: { 'ca:importe__sum': 'column_percent' },
        column_formats: { 'ca:importe__sum': { type: 'percent', decimals: 1 } },
        column_aggregations: { 'ca:importe__sum': 'sum' },
      };
      SavedReportPanelsAPI.show.mockResolvedValue({
        data: {
          name: 'Dynamic',
          date_preset: 'last_7_days',
          filters: [],
          widgets: [widget],
        },
      });
      wrapper = mountEditor(false);
      await flushPromises();
      await vi.advanceTimersByTimeAsync(PREVIEW_DEBOUNCE_MS);
      const previewWidget =
        SavedReportPanelsAPI.preview.mock.lastCall[0].saved_report_panel
          .widgets[0];
      expect(previewWidget).toEqual(widget);
      await wrapper.find('[data-testid="step-3"]').trigger('click');
      await wrapper.find('[data-testid="save-panel"]').trigger('click');
      await flushPromises();
      expect(
        SavedReportPanelsAPI.update.mock.lastCall[1].saved_report_panel
          .widgets[0]
      ).toEqual(widget);
    }
  );
});
