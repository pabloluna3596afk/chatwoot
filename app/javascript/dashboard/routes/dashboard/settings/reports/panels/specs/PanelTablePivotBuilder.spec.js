import { reactive } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import PanelTablePivotBuilder from '../components/PanelTablePivotBuilder.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import esReports from 'dashboard/i18n/locale/es/report.json';

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
    picker('table-group').vm.$emit('update:modelValue', 'inbox_summary');
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
});
