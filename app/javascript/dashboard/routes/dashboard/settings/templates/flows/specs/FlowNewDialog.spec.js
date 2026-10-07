import { mount } from '@vue/test-utils';
import FlowNewDialog from '../FlowNewDialog.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import { startingDefinition } from '../flowDefinition';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
const DialogStub = {
  template: '<div><slot /></div>',
  methods: {
    open() {},
    close() {
      this.$emit('close');
    },
  },
};
let wrapper;
beforeEach(() => {
  wrapper = mount(FlowNewDialog, {
    global: { stubs: { Dialog: DialogStub }, mocks: { $t: key => key } },
  });
  wrapper.vm.open();
});
afterEach(() => wrapper.unmount());
describe('FlowNewDialog', () => {
  it('requires a non-whitespace name and shows validation only after confirm', async () => {
    expect(wrapper.text()).not.toContain('NAME_REQUIRED');
    await wrapper.get('[data-testid="new-flow-name"] input').setValue('  ');
    wrapper.findComponent(DialogStub).vm.$emit('confirm');
    await wrapper.vm.$nextTick();
    expect(wrapper.emitted('create')).toBeUndefined();
    expect(wrapper.text()).toContain('NAME_REQUIRED');
  });
  it('defaults categories to Other and starts with one truly empty screen', async () => {
    await wrapper
      .get('[data-testid="new-flow-name"] input')
      .setValue('  Datos  ');
    wrapper.findComponent(DialogStub).vm.$emit('confirm');
    expect(wrapper.emitted('create')[0][0]).toEqual({
      id: null,
      name: 'Datos',
      categories: ['OTHER'],
      definition: startingDefinition('blank'),
    });
    expect(
      wrapper.emitted('create')[0][0].definition.screens[0].blocks
    ).toEqual([]);
    expect(wrapper.emitted('cancel')).toBeUndefined();
  });
  it.each(['interests', 'feedback', 'survey', 'support'])(
    'applies %s before opening the editor',
    async id => {
      await wrapper
        .get('[data-testid="new-flow-name"] input')
        .setValue('Datos');
      wrapper
        .findComponent(ComboBox)
        .vm.$emit('update:modelValue', ['LEAD_GENERATION', 'SURVEY']);
      await wrapper
        .get(`[data-testid="new-flow-template-${id}"]`)
        .trigger('click');
      wrapper.findComponent(DialogStub).vm.$emit('confirm');
      expect(wrapper.emitted('create')[0][0]).toMatchObject({
        categories: ['LEAD_GENERATION', 'SURVEY'],
        definition: startingDefinition(id),
      });
    }
  );
  it('keeps selection buttons out of form submission and supports arrow keys', async () => {
    const blank = wrapper.get('[data-testid="new-flow-template-blank"]');
    expect(blank.attributes('type')).toBe('button');
    await blank.trigger('keydown', { key: 'ArrowDown' });
    expect(
      wrapper
        .get('[data-testid="new-flow-template-interests"]')
        .attributes('aria-checked')
    ).toBe('true');
  });
  it('cancels without creating and resets the dialog when reopened', async () => {
    await wrapper
      .get('[data-testid="new-flow-name"] input')
      .setValue('Sin guardar');
    wrapper.findComponent(DialogStub).vm.$emit('close');
    expect(wrapper.emitted('cancel')).toHaveLength(1);
    expect(wrapper.emitted('create')).toBeUndefined();
    wrapper.vm.open();
    await wrapper.vm.$nextTick();
    expect(
      wrapper.get('[data-testid="new-flow-name"] input').element.value
    ).toBe('');
  });
});
