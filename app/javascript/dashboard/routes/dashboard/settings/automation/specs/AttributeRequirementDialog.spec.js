import { flushPromises, mount } from '@vue/test-utils';
import AttributeRequirementDialog from '../AttributeRequirementDialog.vue';

const { dispatch, useAlert, existingAttributes } = vi.hoisted(() => ({
  dispatch: vi.fn(),
  useAlert: vi.fn(),
  existingAttributes: { value: [] },
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useFunctionGetter: () => existingAttributes,
}));

vi.mock('dashboard/composables', () => ({ useAlert }));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}:${JSON.stringify(params)}` : key),
  }),
}));

const DialogStub = {
  props: ['disableConfirmButton', 'isLoading'],
  emits: ['confirm', 'close'],
  methods: {
    open() {},
    close() {
      this.$emit('close');
    },
  },
  template: `
    <section>
      <slot />
      <button data-test="confirm" :disabled="disableConfirmButton" @click="$emit('confirm')" />
    </section>
  `,
};

// Real OutlinedSelectField relies on a teleported dropdown-menu that jsdom
// can't render meaningfully; a native <select> exercises the same @select
// contract (emits the full option object, not just its id) without pulling
// in unrelated dropdown internals.
const OutlinedSelectFieldStub = {
  props: ['options', 'selectedItem', 'label'],
  emits: ['select'],
  template: `
    <select
      data-test="attr-select"
      :value="selectedItem?.id"
      @change="$emit('select', options.find(o => String(o.id) === $event.target.value))"
    >
      <option v-for="o in options" :key="o.id" :value="o.id">{{ o.name }}</option>
    </select>
  `,
};

const mountDialog = () =>
  mount(AttributeRequirementDialog, {
    global: {
      stubs: {
        Dialog: DialogStub,
        OutlinedSelectField: OutlinedSelectFieldStub,
      },
    },
  });

const requirement = {
  attributeKey: 'fecha_venta',
  attributeDisplayName: 'Fecha de venta',
  attributeModel: 'conversation_attribute',
  attributeDisplayType: 'date',
};

describe('AttributeRequirementDialog', () => {
  beforeEach(() => {
    existingAttributes.value = [];
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('defaults to "create new" and creates the attribute on confirm, resolving with its key', async () => {
    dispatch.mockResolvedValue({});
    const wrapper = mountDialog();

    const resolved = wrapper.vm.resolve(requirement);
    await flushPromises();

    // Nothing pre-existing matches the placeholder key, so "create new" is selected
    // and the name field is pre-filled from the requirement.
    expect(wrapper.find('input').element.value).toBe('Fecha de venta');

    await wrapper.find('[data-test="confirm"]').trigger('click');
    await flushPromises();

    // convertToAttributeSlug keeps stop words ("de"), so the generated key
    // is fecha_de_venta — it does not need to match the preset's placeholder
    // key (fecha_venta); replaceAttributeKey substitutes whatever key this
    // resolves to, wherever the placeholder appears.
    expect(dispatch).toHaveBeenCalledWith('attributes/create', {
      attribute_display_name: 'Fecha de venta',
      attribute_key: 'fecha_de_venta',
      attribute_model: 'conversation_attribute',
      attribute_display_type: 'date',
      category: '',
    });
    await expect(resolved).resolves.toBe('fecha_de_venta');
  });

  it('passes through the suggested category when the requirement has one', async () => {
    dispatch.mockResolvedValue({});
    const wrapper = mountDialog();

    wrapper.vm.resolve({ ...requirement, category: 'Ventas' });
    await flushPromises();
    await wrapper.find('[data-test="confirm"]').trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith(
      'attributes/create',
      expect.objectContaining({ category: 'Ventas' })
    );
  });

  it('offers an existing attribute of the right model/type and resolves with it without creating one', async () => {
    existingAttributes.value = [
      {
        attribute_key: 'fecha_compra',
        attribute_display_name: 'Fecha de compra',
        attribute_display_type: 'date',
      },
    ];
    const wrapper = mountDialog();

    const resolved = wrapper.vm.resolve(requirement);
    await flushPromises();

    await wrapper.find('[data-test="attr-select"]').setValue('fecha_compra');
    await wrapper.find('[data-test="confirm"]').trigger('click');
    await flushPromises();

    expect(dispatch).not.toHaveBeenCalled();
    await expect(resolved).resolves.toBe('fecha_compra');
  });

  it('does not offer an existing attribute of a different display type', async () => {
    existingAttributes.value = [
      {
        attribute_key: 'monto_venta',
        attribute_display_name: 'Monto',
        attribute_display_type: 'currency',
      },
    ];
    const wrapper = mountDialog();
    wrapper.vm.resolve(requirement);
    await flushPromises();

    const options = wrapper.findAll('[data-test="attr-select"] option');
    expect(options.map(o => o.element.value)).not.toContain('monto_venta');
  });

  it('resolves with null when cancelled', async () => {
    const wrapper = mountDialog();
    const resolved = wrapper.vm.resolve(requirement);
    await flushPromises();

    await wrapper.findComponent(DialogStub).vm.close();
    await flushPromises();

    await expect(resolved).resolves.toBeNull();
    expect(dispatch).not.toHaveBeenCalled();
  });

  it('shows an alert and keeps the dialog open when creation fails', async () => {
    dispatch.mockRejectedValue(new Error('boom'));
    const wrapper = mountDialog();
    wrapper.vm.resolve(requirement);
    await flushPromises();

    await wrapper.find('[data-test="confirm"]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'AUTOMATION.ATTRIBUTE_REQUIREMENT.CREATE_ERROR'
    );
  });
});
