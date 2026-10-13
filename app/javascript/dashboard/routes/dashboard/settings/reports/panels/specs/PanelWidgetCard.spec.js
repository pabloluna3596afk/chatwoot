import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import PanelWidgetCard from '../components/PanelWidgetCard.vue';
import BarChart from 'shared/components/charts/BarChart.vue';
import enReports from 'dashboard/i18n/locale/en/report.json';
import esReports from 'dashboard/i18n/locale/es/report.json';
import { pivotColumnKey } from '../panelConstants';

const mocks = vi.hoisted(() => ({ push: vi.fn() }));
vi.mock('vue-router', () => ({
  useRouter: () => ({ push: mocks.push }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));

let wrapper;
let i18n;
const mountCard = (props, locale = 'es') => {
  i18n = createI18n({
    legacy: false,
    locale,
    fallbackLocale: 'en',
    messages: { en: enReports, es: esReports },
  });
  wrapper = mount(PanelWidgetCard, {
    props,
    global: { plugins: [i18n], stubs: { BarChart: true, Spinner: true } },
  });
  return wrapper;
};

describe('panel table readability', () => {
  afterEach(() => {
    wrapper?.unmount();
    vi.clearAllMocks();
  });

  it('groups three crossed values over two measures, retaining totals and API column order', async () => {
    const measures = ['conversations_count', 'resolved_conversations_count'];
    const segments = ['Calificado', 'En curso', ''];
    const crossed = segments.flatMap(segment =>
      measures.map(measure => pivotColumnKey(measure, segment))
    );
    const columns = ['name', ...crossed, ...measures];
    const row = { name: 'Ana' };
    columns.slice(1).forEach((key, index) => {
      row[key] = index + 1;
    });
    mountCard({
      widget: {
        type: 'table',
        table_kind: 'pivot',
        columns: ['name', ...measures],
        pivot: { row_attribute: 'agent', column_attribute: 'ca:stage' },
      },
      result: {
        columns,
        rows: [row, { ...row, name: 'Luis', [crossed[0]]: 0 }],
      },
    });
    const headerRows = wrapper.findAll('thead tr');
    expect(headerRows).toHaveLength(2);
    const top = headerRows[0].findAll('th');
    expect(top.map(cell => cell.text())).toEqual([
      'Agente',
      'Calificado',
      'En curso',
      '(vacío)',
      'Total',
    ]);
    expect(top[0].attributes('rowspan')).toBe('2');
    top.slice(1).forEach(cell => {
      expect(cell.attributes('colspan')).toBe('2');
      expect(cell.attributes('scope')).toBe('colgroup');
    });
    const lower = headerRows[1].findAll('th');
    expect(lower.map(cell => cell.text())).toEqual(
      segments.concat('Total').flatMap(() => ['Conversaciones', 'Resueltas'])
    );
    expect(lower[0].find('button').attributes('title')).toBe(
      'Calificado · Conversaciones (asignadas)'
    );
    expect(
      wrapper
        .find('tbody tr')
        .findAll('td')
        .map(cell => cell.text())
    ).toEqual(['Ana', '1', '2', '3', '4', '5', '6', '7', '8']);
    await lower[0].find('button').trigger('click');
    expect(wrapper.find('tbody td').text()).toBe('Luis');
    expect(lower[0].attributes('aria-sort')).toBe('ascending');
    expect(lower[1].attributes('aria-sort')).toBe('none');
  });

  it('renders one header row without crossing and sorts raw amounts with Others last', async () => {
    const amount = 'ca:amount__sum';
    const rows = [
      { name: 'Ana', [amount]: 1080 },
      { name: 'Luis', [amount]: 20 },
      { name: 'Other', [amount]: 1, is_others: true },
    ];
    mountCard({
      widget: {
        type: 'table',
        table_kind: 'pivot',
        pivot: { row_attribute: 'agent' },
      },
      attributeLabels: { amount: 'Importe' },
      attributeTypes: { amount: 'currency' },
      result: {
        columns: ['name', amount],
        rows,
        totals: { count: 3, columns: { [amount]: 1101 } },
      },
    });
    expect(wrapper.findAll('thead tr')).toHaveLength(1);
    const header = wrapper.findAll('thead th')[1];
    expect(header.text()).toBe('Importe (suma)');
    expect(header.find('button').attributes('title')).toBe('Suma(Importe)');
    expect(wrapper.findAll('tbody td')[1].text()).toBe('$1.080,00');
    expect(wrapper.findAll('tfoot td')[1].text()).toBe('$1.101,00');
    await header.find('button').trigger('click');
    expect(
      wrapper.findAll('tbody tr').map(row => row.find('td').text())
    ).toEqual(['Luis', 'Ana', 'Otros']);
    await header.find('button').trigger('click');
    expect(
      wrapper.findAll('tbody tr').map(row => row.find('td').text())
    ).toEqual(['Ana', 'Luis', 'Otros']);
    expect(rows[0].name).toBe('Ana');
    expect(wrapper.find('thead th').classes()).toEqual(
      expect.arrayContaining(['sticky', 'start-0', 'bg-n-solid-2'])
    );
    expect(wrapper.find('tbody td').classes()).toEqual(
      expect.arrayContaining(['sticky', 'start-0', 'bg-n-solid-2'])
    );
    expect(wrapper.find('tfoot td').classes()).toEqual(
      expect.arrayContaining(['sticky', 'start-0', 'bg-n-solid-1'])
    );
  });

  it('caps long headers, keeps numeric alignment, and confines horizontal scrolling to the card', () => {
    mountCard({
      widget: { type: 'table', table_kind: 'contacts' },
      attributeLabels: {
        amount: 'Importe personalizado con un nombre muy largo',
      },
      result: {
        columns: ['name', 'ca:amount__sum'],
        rows: [{ name: 'Nombre completo muy largo', 'ca:amount__sum': 1080 }],
      },
    });
    expect(wrapper.classes()).toEqual(
      expect.arrayContaining(['min-w-0', 'max-w-full'])
    );
    expect(wrapper.find('.overflow-x-auto').classes()).toEqual(
      expect.arrayContaining(['min-w-0', 'max-w-full'])
    );
    wrapper.findAll('thead th').forEach(header => {
      expect(header.classes()).not.toContain('whitespace-nowrap');
      expect(header.find('button span').classes()).toContain('truncate');
      expect(header.find('button').attributes('title')).toBeTruthy();
    });
    expect(wrapper.findAll('tbody td')[1].classes()).toEqual(
      expect.arrayContaining(['text-end', 'whitespace-nowrap'])
    );
  });

  it('formats dates, counts, configured percentages and currency reactively in the current locale', async () => {
    mountCard({
      widget: {
        type: 'table',
        table_kind: 'contacts',
        column_formats: {
          'ca:amount': { type: 'currency', currency_symbol: '$', decimals: 2 },
          'ca:ratio': { type: 'percent', decimals: 1 },
        },
      },
      result: {
        columns: [
          'name',
          'created_at',
          'conversations_count',
          'ca:amount',
          'ca:ratio',
        ],
        rows: [
          {
            name: 'Ana',
            created_at: new Date(2026, 0, 15, 12).getTime() / 1000,
            conversations_count: 1080,
            'ca:amount': 1080.5,
            'ca:ratio': 25.5,
          },
        ],
      },
    });
    let cells = wrapper.findAll('tbody td');
    expect(cells[1].text()).toContain('ene');
    expect(cells.slice(2).map(cell => cell.text())).toEqual([
      '1.080',
      '$1.080,50',
      '25,5%',
    ]);
    i18n.global.locale.value = 'en';
    await flushPromises();
    cells = wrapper.findAll('tbody td');
    expect(cells[1].text()).toContain('Jan');
    expect(cells.slice(2).map(cell => cell.text())).toEqual([
      '1,080',
      '$1,080.50',
      '25.5%',
    ]);
  });

  it('localizes date row buckets and crossed date headings without shifting the calendar date', () => {
    const column = pivotColumnKey('conversations_count', '2026-01-15');
    mountCard({
      widget: {
        type: 'table',
        table_kind: 'pivot',
        pivot: {
          row_attribute: 'created_at',
          row_granularity: 'month',
          column_attribute: 'ca:sale_date',
        },
      },
      attributeTypes: { sale_date: 'date' },
      result: {
        columns: ['name', column],
        rows: [{ name: '2026-01-01', [column]: 7 }],
      },
    });
    expect(wrapper.find('tbody td').text()).toBe('ene 2026');
    const group = wrapper.find('th[scope="colgroup"]');
    expect(group.text()).toContain('15');
    expect(group.text()).toContain('ene');
    expect(
      group.attributes('title') || group.find('span').attributes('title')
    ).toBe(group.text());
  });

  it('uses the same locale for chart preview dates and values', () => {
    mountCard({
      widget: {
        type: 'chart',
        metric: 'conversations_count',
        group_by: 'month',
      },
      result: {
        points: [
          {
            timestamp: new Date(2026, 0, 15, 12).getTime() / 1000,
            value: 1080,
          },
        ],
      },
    });
    const chart = wrapper.findComponent(BarChart);
    expect(chart.props('data').categories).toEqual(['ene 2026']);
    expect(chart.vm.$attrs['format-value'](1080)).toBe('1.080');
  });

  it('keeps the loading, error and empty states mutually exclusive, including refresh failures', async () => {
    mountCard({
      widget: { type: 'table', table_kind: 'contacts' },
      loading: true,
    });
    expect(wrapper.attributes('aria-busy')).toBe('true');
    expect(wrapper.find('[role="status"]').text()).toBe('Cargando datos…');
    expect(wrapper.find('table').exists()).toBe(false);
    await wrapper.setProps({
      loading: false,
      error: 'No se pudo ejecutar el panel',
    });
    expect(wrapper.find('[role="alert"]').text()).toBe(
      'No se pudo ejecutar el panel'
    );
    expect(wrapper.text()).not.toContain('Sin filas');
    await wrapper.setProps({ error: '', result: { rows: [] } });
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(wrapper.find('[role="status"]').text()).toBe(
      'Sin filas en este período.'
    );
    await wrapper.setProps({
      result: { error: 'pivot_row_limit_exceeded:1001' },
    });
    expect(wrapper.find('[role="alert"]').text()).toContain('1000 filas');
    expect(wrapper.text()).not.toContain('Sin filas');
    await wrapper.setProps({
      error: 'No se pudo ejecutar el panel',
      result: { columns: ['name'], rows: [{ name: 'Resultado anterior' }] },
    });
    expect(wrapper.find('table').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('Resultado anterior');
  });

  it('shows a translated execution error for backend failures', () => {
    mountCard(
      {
        widget: { type: 'table', table_kind: 'contacts' },
        result: { error: 'unknown_pivot_attribute' },
      },
      'en'
    );
    expect(wrapper.find('[role="alert"]').text()).toBe('Could not run panel');
    expect(wrapper.text()).not.toContain('unknown_pivot_attribute');
  });

  it('preserves navigation from detail rows', async () => {
    mountCard({
      widget: { type: 'table', table_kind: 'contacts' },
      result: { columns: ['name'], rows: [{ id: 42, name: 'Ana' }] },
    });
    await wrapper.find('tbody tr').trigger('click');
    expect(mocks.push).toHaveBeenCalledWith({
      name: 'contacts_edit',
      params: { contactId: 42 },
    });
  });
});
