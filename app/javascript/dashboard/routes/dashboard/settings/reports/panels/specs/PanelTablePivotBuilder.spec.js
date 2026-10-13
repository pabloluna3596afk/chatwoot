import { reactive } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import PanelTablePivotBuilder from '../components/PanelTablePivotBuilder.vue';
import PanelWidgetCard from '../components/PanelWidgetCard.vue';
import { formatPanelMeasure } from '../panelConstants';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import esReports from 'dashboard/i18n/locale/es/report.json';

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedRoute: vi.fn() }),
}));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));

let wrapper;
let widget;
const picker = id =>
  wrapper
    .findAllComponents(ComboBox)
    .find(box => box.attributes('data-testid') === id);

describe('guided table measures', () => {
  beforeEach(() => {
    widget = reactive({
      id: 'table',
      type: 'table',
      table_kind: 'agent_summary',
      columns: ['rank', 'name', 'ca:importe__count'],
      column_aggregations: { 'ca:importe__count': 'sum' },
      pivot: { column_attribute: '', column_values: [], show_row_totals: true },
    });
    wrapper = mount(PanelTablePivotBuilder, {
      props: {
        widget,
        tableKindOptions: [
          { value: 'agent_summary', label: 'Agente' },
          { value: 'inbox_summary', label: 'Bandeja' },
        ],
        conversationAttributes: [
          {
            attribute_key: 'importe',
            attribute_display_name: 'Importe',
            attribute_display_type: 'currency',
          },
          {
            attribute_key: 'etapa',
            attribute_display_name: 'Etapa',
            attribute_display_type: 'list',
            attribute_values: ['Ganada', 'Nueva'],
          },
        ],
        contactAttributes: [
          {
            attribute_key: 'ventas',
            attribute_display_name: 'Ventas',
            attribute_display_type: 'number',
          },
        ],
      },
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
      },
    });
  });
  afterEach(() => wrapper.unmount());

  it('shows measure and operation separately and changes the encoded measure instead of the footer', async () => {
    expect(wrapper.text()).toContain('Medida');
    expect(wrapper.text()).toContain('Operación');
    expect(picker('measure-field').props('modelValue')).toBe('ca:importe');
    expect(picker('measure-operation').props('modelValue')).toBe('count');
    picker('measure-operation').vm.$emit('update:modelValue', 'sum');
    await wrapper.vm.$nextTick();
    expect(widget.columns).toEqual(['rank', 'name', 'ca:importe__sum']);
    expect(widget.column_aggregations).toEqual({ 'ca:importe__sum': 'sum' });
    expect(picker('measure-operation').props('modelValue')).toBe('sum');
    expect(wrapper.find('select').exists()).toBe(false);
  });

  it('offers only count for text fields and encodes contact measures with their existing prefix', async () => {
    picker('add-measure-field').vm.$emit('update:modelValue', 'ca:etapa');
    await wrapper.vm.$nextTick();
    expect(
      picker('add-measure-operation')
        .props('options')
        .map(item => item.value)
    ).toEqual(['count']);
    await wrapper.find('[data-testid="add-measure"]').trigger('click');
    expect(widget.columns).toContain('ca:etapa__count');
    picker('add-measure-field').vm.$emit(
      'update:modelValue',
      'contact_ca:ventas'
    );
    await wrapper.vm.$nextTick();
    picker('add-measure-operation').vm.$emit('update:modelValue', 'avg');
    await wrapper.vm.$nextTick();
    await wrapper.find('[data-testid="add-measure"]').trigger('click');
    expect(widget.columns).toContain('contact_ca:ventas__avg');
  });

  it('preserves an existing value condition when changing a measure operation', async () => {
    widget.columns = ['rank', 'name', 'ca:importe__count__eq__10'];
    await wrapper.vm.$nextTick();
    picker('measure-operation').vm.$emit('update:modelValue', 'avg');
    await wrapper.vm.$nextTick();
    expect(widget.columns).toContain('ca:importe__avg__eq__10');
  });

  it('keeps an existing selection when a duplicate measure would replace another one', async () => {
    widget.columns.push('ca:importe__sum');
    await wrapper.vm.$nextTick();
    picker('measure-operation').vm.$emit('update:modelValue', 'sum');
    await wrapper.vm.$nextTick();
    expect(widget.columns).toEqual([
      'rank',
      'name',
      'ca:importe__count',
      'ca:importe__sum',
    ]);
  });

  it('emits table grouping changes and uses the same menus for detail columns', async () => {
    picker('pivot-rows').vm.$emit('update:modelValue', 'inbox');
    expect(wrapper.emitted('tableKindChange')).toEqual([['inbox_summary']]);
    widget.table_kind = 'conversations';
    widget.columns = ['id', 'status'];
    await wrapper.vm.$nextTick();
    picker('detail-columns').vm.$emit('update:modelValue', [
      'id',
      'ca:importe',
    ]);
    await wrapper.vm.$nextTick();
    expect(widget.columns).toEqual(['id', 'ca:importe']);
    expect(wrapper.find('select').exists()).toBe(false);
  });

  it('preserves legacy options without writing new keys just by opening the builder', () => {
    expect(widget.pivot).toEqual({
      column_attribute: '',
      column_values: [],
      show_row_totals: true,
    });
    expect(widget.sort).toBeUndefined();
    expect(widget.top_n).toBeUndefined();
    expect(widget.measure_display).toBeUndefined();
    expect(widget.column_formats).toBeUndefined();
    expect(picker('pivot-rows').props('modelValue')).toBe('agent');
    expect(wrapper.find('select').exists()).toBe(false);
  });

  it('offers scalar conversation/contact rows and shows granularity only for creation dates', async () => {
    expect(
      picker('pivot-rows')
        .props('options')
        .map(option => option.value)
    ).toEqual(
      expect.arrayContaining([
        'agent',
        'inbox',
        'team',
        'label',
        'created_at',
        'ca:importe',
        'ca:etapa',
        'contact_ca:ventas',
      ])
    );
    expect(picker('granularity')).toBeUndefined();
    picker('pivot-rows').vm.$emit('update:modelValue', 'created_at');
    await wrapper.vm.$nextTick();
    expect(widget.pivot).toMatchObject({
      row_attribute: 'created_at',
      row_granularity: 'day',
    });
    expect(picker('sort_column').props('modelValue')).toBe('name');
    expect(picker('sort_direction').props('modelValue')).toBe('asc');
    picker('granularity').vm.$emit('update:modelValue', 'week');
    expect(widget.pivot.row_granularity).toBe('week');
    picker('pivot-rows').vm.$emit('update:modelValue', 'contact_ca:ventas');
    await wrapper.vm.$nextTick();
    expect(widget.pivot.row_granularity).toBeUndefined();
    expect(picker('granularity')).toBeUndefined();
  });

  it('offers supported limits, independent Top N measures and disables Others for contacts', async () => {
    expect(
      picker('top_limit')
        .props('options')
        .map(option => option.value)
    ).toEqual(['', 5, 10, 20]);
    picker('top_limit').vm.$emit('update:modelValue', 5);
    await wrapper.vm.$nextTick();
    expect(widget.top_n).toEqual({
      limit: 5,
      column: 'ca:importe__count',
      include_others: false,
    });
    widget.top_n.include_others = true;
    picker('add-measure-field').vm.$emit(
      'update:modelValue',
      'contact_ca:ventas'
    );
    await wrapper.vm.$nextTick();
    await wrapper.find('[data-testid="add-measure"]').trigger('click');
    expect(widget.top_n.include_others).toBe(false);
    expect(
      wrapper.find('[data-testid="include-others"]').attributes('disabled')
    ).toBeDefined();
  });

  it('remaps formats and sort on operation changes and clears unsupported percentage displays', async () => {
    widget.sort = { column: 'ca:importe__count', direction: 'desc' };
    widget.top_n = {
      limit: 5,
      column: 'ca:importe__count',
      include_others: false,
    };
    picker('measure-display').vm.$emit('update:modelValue', 'row_percent');
    picker('measure-format').vm.$emit('update:modelValue', 'currency');
    await wrapper.vm.$nextTick();
    picker('measure-operation').vm.$emit('update:modelValue', 'avg');
    await wrapper.vm.$nextTick();
    expect(widget.sort.column).toBe('ca:importe__avg');
    expect(widget.top_n.column).toBe('ca:importe__avg');
    expect(widget.column_formats).toEqual({
      'ca:importe__avg': { type: 'currency' },
    });
    expect(widget.measure_display).toEqual({});
    expect(
      picker('measure-display')
        .props('options')
        .map(option => option.value)
    ).toEqual(['value']);
    picker('format-decimals').vm.$emit('update:modelValue', 1);
    expect(widget.column_formats['ca:importe__avg'].decimals).toBe(1);
  });

  it('removes dependent options with a deleted measure and uses discovered expanded columns in pickers', async () => {
    widget.columns.push('conversations_count');
    widget.column_formats = { 'ca:importe__count': { type: 'integer' } };
    widget.measure_display = { 'ca:importe__count': 'column_percent' };
    widget.sort = {
      column: 'ca:importe__count__pv__Ganada',
      direction: 'desc',
    };
    widget.top_n = {
      limit: 10,
      column: 'ca:importe__count',
      include_others: false,
    };
    widget.pivot.column_attribute = 'ca:etapa';
    await wrapper.setProps({
      previewPivot: {
        column_attribute: 'ca:etapa',
        column_values: ['Discovered'],
      },
    });
    expect(
      picker('sort_column')
        .props('options')
        .map(option => option.value)
    ).toContain('conversations_count__pv__Discovered');
    await wrapper
      .find('[data-testid="measure-row"] button[aria-label="Quitar medida"]')
      .trigger('click');
    expect(widget.column_formats).toEqual({});
    expect(widget.measure_display).toEqual({});
    expect(widget.sort).toBeUndefined();
    expect(widget.top_n).toBeUndefined();
  });

  it('formats crossed cells and footers from the base measure, preserves saved order and pins Others during local sorting', async () => {
    wrapper.unmount();
    const column = 'ca:importe__sum__pv__A';
    const config = { type: 'currency', currency_symbol: 'EUR ', decimals: 1 };
    const rows = [
      { id: 'b', name: 'B', [column]: 10.9 },
      { id: 'a', name: 'A', [column]: 10.1 },
      { id: '__others__', name: '', is_others: true, [column]: 30 },
    ];
    const result = {
      columns: ['name', column],
      rows,
      pivot: { row_attribute: 'created_at' },
      totals: { count: 3, columns: { [column]: 51 }, ops: { [column]: 'sum' } },
    };
    wrapper = mount(PanelWidgetCard, {
      props: {
        widget: {
          type: 'table',
          table_kind: 'agent_summary',
          columns: ['name', 'ca:importe__sum'],
          column_formats: { 'ca:importe__sum': config },
          sort: { column, direction: 'desc' },
        },
        result,
      },
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
      },
    });
    expect(
      wrapper.findAll('tbody tr').map(row => row.find('td').text())
    ).toEqual(['B', 'A', 'Otros']);
    expect(wrapper.find('tbody').text()).toContain(
      formatPanelMeasure(10.9, config)
    );
    expect(wrapper.find('tfoot').text()).toContain(
      formatPanelMeasure(51, config)
    );
    expect(wrapper.find('thead').text()).toContain('Fecha de creación');
    await wrapper.findAll('thead th')[1].trigger('click');
    expect(
      wrapper.findAll('tbody tr').map(row => row.find('td').text())
    ).toEqual(['A', 'B', 'Otros']);
    await wrapper.findAll('thead th')[1].trigger('click');
    expect(
      wrapper.findAll('tbody tr').map(row => row.find('td').text())
    ).toEqual(['B', 'A', 'Otros']);
    await wrapper.setProps({ result: { ...result, rows: [...rows] } });
    expect(
      wrapper.findAll('tbody tr').map(row => row.find('td').text())
    ).toEqual(['B', 'A', 'Otros']);
  });
});
