import { flushPromises, mount } from '@vue/test-utils';
import { startingDefinition } from '../flowDefinition';
import FlowBuilderPage from '../FlowBuilderPage.vue';
import FlowPhoneCanvas from '../FlowPhoneCanvas.vue';
import Draggable from 'vuedraggable';
import { createStore } from 'vuex';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, args) => (args ? `${key} ${JSON.stringify(args)}` : key),
    te: () => false,
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/whatsappFlows', () => ({
  default: { validate: vi.fn(), create: vi.fn(), update: vi.fn() },
}));

const DialogStub = {
  name: 'Dialog',
  props: ['title'],
  data: () => ({ isOpen: false }),
  methods: {
    open() {
      this.isOpen = true;
    },
    close() {
      this.isOpen = false;
    },
  },
  template:
    '<div v-if="isOpen" :data-title="title"><slot /><slot name="footer" /><button data-testid="stub-confirm" @click="$emit(\'confirm\')" /></div>',
};

const makeApi = () => ({
  validate: vi.fn().mockResolvedValue({
    data: { valid: true, errors: [], flow_json: { version: '7.3' } },
  }),
  create: vi.fn().mockResolvedValue({ data: { id: 9, name: 'Datos' } }),
  update: vi.fn().mockResolvedValue({ data: { id: 9, name: 'Datos 2' } }),
});

const sampleFlow = (extra = {}) => ({
  id: 7,
  name: 'Datos',
  categories: ['LEAD_GENERATION'],
  definition: {
    schema_version: 1,
    screens: [
      {
        title: 'Tus datos',
        button: 'Continuar',
        blocks: [
          { type: 'short_text', key: 'nombre', label: 'Nombre', input: 'text' },
          {
            type: 'short_text',
            key: 'correo',
            label: 'Correo',
            input: 'email',
          },
        ],
      },
      {
        title: 'Tu cita',
        button: 'Enviar',
        blocks: [
          {
            type: 'radio',
            key: 'necesitas',
            label: '¿Qué necesitas?',
            options: [
              { id: 'consulta', title: 'Consulta' },
              { id: 'otro', title: 'Otro' },
            ],
          },
          {
            type: 'long_text',
            key: 'mas',
            label: 'Cuéntanos más',
            visible_when: { key: 'necesitas', op: 'equals', value: 'otro' },
          },
        ],
      },
    ],
  },
  ...extra,
});

const mountPage = async (flow = sampleFlow(), api = makeApi()) => {
  const wrapper = mount(FlowBuilderPage, {
    props: { flow, api },
    global: {
      plugins: [
        createStore({
          modules: {
            attributes: {
              namespaced: true,
              getters: { getAttributes: () => [] },
              actions: { get: vi.fn() },
            },
          },
        }),
      ],
      mocks: { $t: key => key },
      stubs: { Dialog: DialogStub },
    },
  });
  await flushPromises();
  return { wrapper, api };
};

const tabs = wrapper => wrapper.findAll('[data-testid="flow-screen-tab"]');
const canvasBlocks = wrapper =>
  wrapper.findAll('[data-testid="flow-canvas-block"]');

describe('FlowBuilderPage', () => {
  it('dims the existing panels in Try, resets on mode exit and never sends simulator answers to the API', async () => {
    const { wrapper, api } = await mountPage();
    const original = JSON.stringify(
      wrapper.findComponent(FlowPhoneCanvas).props('definition')
    );
    const calls = api.validate.mock.calls.length;
    await wrapper.get('[data-testid="flow-preview-try"]').trigger('click');
    expect(
      wrapper.get('[data-testid="flow-palette"]').attributes()
    ).toHaveProperty('inert');
    expect(
      wrapper.get('[data-testid="flow-properties"]').attributes()
    ).toHaveProperty('inert');
    expect(
      wrapper.get('[data-testid="flow-editor-save"]').attributes()
    ).toHaveProperty('disabled');
    await wrapper.get('#flow-preview-nombre').setValue('Local only');
    await wrapper.get('[data-testid="flow-preview-edit"]').trigger('click');
    expect(
      JSON.stringify(wrapper.findComponent(FlowPhoneCanvas).props('definition'))
    ).toBe(original);
    await wrapper.get('[data-testid="flow-preview-try"]').trigger('click');
    expect(wrapper.get('#flow-preview-nombre').element.value).toBe('');
    expect(api.validate).toHaveBeenCalledTimes(calls);
    expect(api.create).not.toHaveBeenCalled();
    expect(api.update).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('shows Saved only for a saved snapshot and Unsaved changes until a successful save', async () => {
    const { wrapper, api } = await mountPage();
    const subtitle = () =>
      wrapper.get('[data-testid="flow-save-state"]').text();
    expect(subtitle()).toBe('WHATSAPP_FLOWS.EDITOR.SAVE_STATE');
    await wrapper
      .get('[data-testid="flow-editor-name"] input')
      .setValue('New name');
    expect(subtitle()).toBe('WHATSAPP_FLOWS.EDITOR.UNSAVED');
    expect(wrapper.get('[data-testid="flow-editor-save"]').exists()).toBe(true);
    api.update.mockRejectedValueOnce(new Error('Failed'));
    await wrapper.get('[data-testid="flow-editor-save"]').trigger('click');
    await flushPromises();
    expect(subtitle()).toBe('WHATSAPP_FLOWS.EDITOR.UNSAVED');
    await wrapper.get('[data-testid="flow-editor-save"]').trigger('click');
    await flushPromises();
    expect(subtitle()).toBe('WHATSAPP_FLOWS.EDITOR.SAVE_STATE');
    wrapper.unmount();
    const fresh = await mountPage(sampleFlow({ id: null }));
    expect(fresh.wrapper.get('[data-testid="flow-save-state"]').text()).toBe(
      'WHATSAPP_FLOWS.EDITOR.UNSAVED'
    );
  });

  it('shows saved unpublished changes immediately after saving an edit', async () => {
    const api = makeApi();
    api.publicationStatus = vi.fn().mockResolvedValue({
      data: { unpublished_changes: false, wabas: [], publications: [] },
    });
    api.update.mockResolvedValue({
      data: { id: 7, unpublished_changes: true },
    });
    const { wrapper } = await mountPage(sampleFlow(), api);
    await wrapper
      .get('[data-testid="flow-editor-name"] input')
      .setValue('Updated form');
    api.publicationStatus.mockReturnValue(new Promise(() => {}));
    await wrapper.get('[data-testid="flow-editor-save"]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-testid="flow-editor-status"]').trigger('click');
    expect(
      wrapper.find('[data-testid="flow-unpublished-banner"]').exists()
    ).toBe(true);
  });

  it('explains unpublished changes without duplicating the publish action', async () => {
    const api = makeApi();
    api.publicationStatus = vi.fn().mockResolvedValue({
      data: {
        unpublished_changes: true,
        wabas: [{ waba_id: '111', channel_id: 7, phone_number: '+593990001' }],
        publications: [],
      },
    });
    const { wrapper } = await mountPage(
      sampleFlow({ unpublished_changes: true }),
      api
    );
    await wrapper.get('[data-testid="flow-editor-status"]').trigger('click');
    expect(
      wrapper.get('[data-testid="flow-unpublished-banner"]').text()
    ).toContain('UNPUBLISHED_CHANGES_BANNER');
    expect(
      wrapper.find('[data-testid="flow-unpublished-publish"]').exists()
    ).toBe(false);
    expect(wrapper.findAll('[data-testid="flow-publish-open"]')).toHaveLength(
      1
    );
  });

  it('never presents the starting chooser inside an editor', async () => {
    const { wrapper } = await mountPage(sampleFlow({ id: null }));
    expect(wrapper.find('[data-testid="flow-starting"]').exists()).toBe(false);
    expect(canvasBlocks(wrapper)).toHaveLength(2);
  });

  describe('screens as tabs above the phone', () => {
    it('has a tab per screen and the "+ Pantalla" tab at the end of the row', async () => {
      const { wrapper } = await mountPage();

      expect(tabs(wrapper)).toHaveLength(2);
      expect(tabs(wrapper)[0].text()).toContain('Tus datos');
      expect(tabs(wrapper)[0].text()).toContain('"n":1');
      const row = wrapper.get('[data-testid="flow-screen-tabs"]');
      expect(
        row
          .get('[data-testid="flow-screen-add"]')
          .element.previousElementSibling.getAttribute('data-testid')
      ).toBe('flow-screen-draggable');
    });

    it('shows the screen of the tab clicked in the phone', async () => {
      const { wrapper } = await mountPage();
      expect(canvasBlocks(wrapper)).toHaveLength(2);

      await tabs(wrapper)[1].trigger('click');

      expect(tabs(wrapper)[1].attributes('aria-selected')).toBe('true');
      expect(wrapper.findComponent(FlowPhoneCanvas).props('screenIndex')).toBe(
        1
      );
      expect(canvasBlocks(wrapper)[0].text()).toContain('¿Qué necesitas?');
    });

    it('adds a screen with "+ Pantalla" and opens it', async () => {
      const { wrapper } = await mountPage();

      await wrapper.get('[data-testid="flow-screen-add"]').trigger('click');

      expect(tabs(wrapper)).toHaveLength(3);
      expect(tabs(wrapper)[2].attributes('aria-selected')).toBe('true');
      expect(tabs(wrapper)[2].text()).toContain('Pantalla 3');
    });

    it('removes a screen with its × and keeps at least one', async () => {
      const { wrapper } = await mountPage();

      await wrapper
        .findAll('[data-testid="flow-screen-remove"]')[1]
        .trigger('click');

      expect(tabs(wrapper)).toHaveLength(1);
      expect(wrapper.find('[data-testid="flow-screen-remove"]').exists()).toBe(
        false
      );
    });

    it('has no "add screen" button at the bottom of the page', async () => {
      const { wrapper } = await mountPage();

      expect(wrapper.findAll('[data-testid="flow-screen-add"]')).toHaveLength(
        1
      );
    });

    it('has no "Move screen" buttons any more', async () => {
      const { wrapper } = await mountPage();

      expect(wrapper.find('[data-testid="flow-screen-left"]').exists()).toBe(
        false
      );
      expect(wrapper.find('[data-testid="flow-screen-right"]').exists()).toBe(
        false
      );
    });

    it('reorders the tabs when one is dragged, and the selected screen stays selected', async () => {
      const { wrapper } = await mountPage();
      const draggable = wrapper.findComponent(Draggable);
      const [first, second] = draggable.props('modelValue');

      draggable.vm.$emit('update:modelValue', [second, first]);
      await flushPromises();

      expect(tabs(wrapper)[0].text()).toContain('Tu cita');
      expect(tabs(wrapper)[1].text()).toContain('Tus datos');
      expect(tabs(wrapper)[1].attributes('aria-selected')).toBe('true');
    });

    it('keeps "+ Pantalla" after the tabs and out of the drag list', async () => {
      const { wrapper } = await mountPage();

      const draggable = wrapper.findComponent(Draggable);
      expect(draggable.find('[data-testid="flow-screen-add"]').exists()).toBe(
        false
      );
      expect(
        wrapper.get('[data-testid="flow-screen-add"]').element
          .previousElementSibling
      ).toBe(draggable.element);
    });

    it('moves the focused tab with Alt + arrow keys and announces it', async () => {
      const { wrapper } = await mountPage();
      const first = tabs(wrapper)[0];

      expect(first.attributes('aria-keyshortcuts')).toContain('Alt+ArrowRight');
      await first.trigger('keydown', { key: 'ArrowRight', altKey: true });

      expect(tabs(wrapper)[1].text()).toContain('Tus datos');
      expect(tabs(wrapper)[1].attributes('aria-selected')).toBe('true');
      expect(wrapper.get('[role="status"]').text()).toContain(
        'WHATSAPP_FLOWS.EDITOR.TAB_MOVED'
      );

      await tabs(wrapper)[1].trigger('keydown', {
        key: 'ArrowLeft',
        ctrlKey: true,
      });
      expect(tabs(wrapper)[0].text()).toContain('Tus datos');
    });

    it('ignores the arrow keys at the ends and without a modifier', async () => {
      const { wrapper } = await mountPage();

      await tabs(wrapper)[0].trigger('keydown', {
        key: 'ArrowLeft',
        altKey: true,
      });
      await tabs(wrapper)[0].trigger('keydown', { key: 'ArrowRight' });

      expect(tabs(wrapper)[0].text()).toContain('Tus datos');
    });
  });

  describe('blocks are edited by clicking them on the phone', () => {
    it('shows only the settings of the selected block, not a card per block', async () => {
      const { wrapper } = await mountPage();

      expect(wrapper.find('[data-testid="flow-block"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="flow-form-props"]').exists()).toBe(
        true
      );

      await canvasBlocks(wrapper)[1].trigger('click');

      expect(wrapper.findAll('[data-testid="flow-block"]')).toHaveLength(1);
      expect(wrapper.find('[data-testid="flow-form-props"]').exists()).toBe(
        false
      );
      expect(canvasBlocks(wrapper)[1].attributes('data-selected')).toBe('true');
      expect(canvasBlocks(wrapper)[0].attributes('data-selected')).toBe(
        'false'
      );
    });

    it('edits the block from the right column and the phone follows', async () => {
      const { wrapper } = await mountPage();
      await canvasBlocks(wrapper)[0].trigger('click');

      await wrapper
        .get('[data-testid="flow-block-label"] input')
        .setValue('Nombre completo');

      expect(canvasBlocks(wrapper)[0].text()).toContain('Nombre completo');
    });

    it('adds a block from the left column to the current screen and selects it', async () => {
      const { wrapper } = await mountPage();
      await tabs(wrapper)[1].trigger('click');

      await wrapper.get('[data-testid="flow-add-email"]').trigger('click');

      expect(canvasBlocks(wrapper)).toHaveLength(3);
      expect(canvasBlocks(wrapper)[2].attributes('data-selected')).toBe('true');
      expect(wrapper.find('[data-testid="flow-block-props"]').exists()).toBe(
        true
      );
    });

    it('groups the buttons as text, answers, options and files', async () => {
      const { wrapper } = await mountPage();

      const groups = wrapper
        .get('[data-testid="flow-palette"]')
        .findAll('p')
        .map(group => group.text());
      expect(groups).toEqual([
        'WHATSAPP_FLOWS.EDITOR.GROUPS.text',
        'WHATSAPP_FLOWS.EDITOR.GROUPS.answer',
        'WHATSAPP_FLOWS.EDITOR.GROUPS.options',
        'WHATSAPP_FLOWS.EDITOR.GROUPS.file',
      ]);
    });

    it('keeps two palette columns and a wider properties panel', async () => {
      const { wrapper } = await mountPage();

      const group = wrapper.get('[data-testid="flow-palette"] > div');
      expect(group.classes()).toContain('grid-cols-2');
      expect(wrapper.html()).toContain(
        'min-[1100px]:grid-cols-[16rem_minmax(0,1fr)_22.5rem]'
      );
    });

    it('removes the selected block from the phone', async () => {
      const { wrapper } = await mountPage();
      await canvasBlocks(wrapper)[0].trigger('click');

      await wrapper.get('[data-testid="flow-canvas-remove"]').trigger('click');

      expect(canvasBlocks(wrapper)).toHaveLength(1);
      expect(wrapper.find('[data-testid="flow-block-props"]').exists()).toBe(
        false
      );
    });

    it('moves the selected block down', async () => {
      const { wrapper } = await mountPage();
      await canvasBlocks(wrapper)[0].trigger('click');

      await wrapper.get('[data-testid="flow-canvas-down"]').trigger('click');

      expect(canvasBlocks(wrapper)[1].text()).toContain('Nombre');
      expect(canvasBlocks(wrapper)[1].attributes('data-selected')).toBe('true');
    });

    it('leaves the block unselected when changing screens', async () => {
      const { wrapper } = await mountPage();
      await canvasBlocks(wrapper)[0].trigger('click');

      await tabs(wrapper)[1].trigger('click');

      expect(wrapper.find('[data-testid="flow-block-props"]').exists()).toBe(
        false
      );
    });
  });

  describe('the condition of a field', () => {
    it('shows on the phone as a chip and in "Mostrar este campo" when the block is selected', async () => {
      const { wrapper } = await mountPage();
      await tabs(wrapper)[1].trigger('click');
      expect(
        canvasBlocks(wrapper)[1]
          .find('[data-testid="flow-canvas-cond"]')
          .exists()
      ).toBe(true);

      await canvasBlocks(wrapper)[1].trigger('click');

      expect(
        wrapper.findComponent('[data-testid="flow-show"]').props('modelValue')
      ).toBe('necesitas');
    });
  });

  describe('header', () => {
    it('keeps Save visible, groups secondary actions and uses a compact category multiselect', async () => {
      const { wrapper } = await mountPage();

      expect(wrapper.find('[data-testid="flow-json-toggle"]').exists()).toBe(
        false
      );
      expect(
        wrapper.get('[data-testid="flow-editor-name"] input').element.value
      ).toBe('Datos');
      expect(wrapper.find('[data-testid="flow-editor-status"]').exists()).toBe(
        true
      );
      await wrapper.get('[data-testid="flow-actions"]').trigger('click');
      expect(wrapper.get('[data-testid="flow-json-toggle"]').text()).toBe(
        'WHATSAPP_FLOWS.EDITOR.SHOW_JSON'
      );
      expect(wrapper.find('[data-testid="flow-json"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="flow-editor-save"]').exists()).toBe(
        true
      );
      expect(wrapper.find('input[type="checkbox"]').exists()).toBe(false);
      expect(wrapper.findAll('select')).toHaveLength(0);
      expect(
        wrapper
          .findComponent('[data-testid="flow-category-select"]')
          .props('modelValue')
      ).toEqual(['LEAD_GENERATION']);
      expect(wrapper.find('[data-testid="flow-details-open"]').exists()).toBe(
        false
      );
    });

    it('keeps the header slim and moves categories and name into the editor', async () => {
      const { wrapper } = await mountPage();

      const ids = [
        'flow-editor-back',
        'flow-editor-status',
        'flow-editor-category',
        'flow-actions',
        'flow-editor-save',
        'flow-editor-name',
      ];
      const html = wrapper.html();
      const positions = ids.map(id => html.indexOf(`data-testid="${id}"`));
      expect(positions.every(position => position > -1)).toBe(true);
      expect(positions).toEqual([...positions].sort((x, y) => x - y));
    });

    it('opens the JSON Meta will get in a modal, not inside the page', async () => {
      const { wrapper } = await mountPage();
      expect(wrapper.find('[data-testid="flow-json"]').exists()).toBe(false);

      await wrapper.get('[data-testid="flow-actions"]').trigger('click');
      await wrapper.get('[data-testid="flow-json-toggle"]').trigger('click');

      expect(wrapper.find('[data-testid="flow-json-toggle"]').exists()).toBe(
        false
      );
      const modal = wrapper.get('[data-testid="flow-json-dialog"]');
      expect(modal.get('[data-testid="flow-json"]').text()).toContain('7.3');
      expect(modal.get('[data-testid="flow-json"]').classes()).toContain(
        'font-mono'
      );
    });

    it('copies the JSON and says "Copiado"', async () => {
      const writeText = vi.fn().mockResolvedValue();
      Object.defineProperty(navigator, 'clipboard', {
        value: { writeText },
        configurable: true,
      });
      const { wrapper } = await mountPage();
      await wrapper.get('[data-testid="flow-actions"]').trigger('click');
      await wrapper.get('[data-testid="flow-json-toggle"]').trigger('click');
      const copy = wrapper.get('[data-testid="flow-json-copy"]');
      expect(copy.text()).toBe('WHATSAPP_FLOWS.EDITOR.JSON_COPY');

      await copy.trigger('click');
      await flushPromises();

      expect(writeText).toHaveBeenCalledWith(
        JSON.stringify({ version: '7.3' }, null, 2)
      );
      expect(wrapper.get('[data-testid="flow-json-copy"]').text()).toBe(
        'WHATSAPP_FLOWS.EDITOR.JSON_COPIED'
      );
    });

    it('closes the JSON modal', async () => {
      const { wrapper } = await mountPage();
      await wrapper.get('[data-testid="flow-actions"]').trigger('click');
      await wrapper.get('[data-testid="flow-json-toggle"]').trigger('click');

      await wrapper.get('[data-testid="flow-json-close"]').trigger('click');

      expect(wrapper.find('[data-testid="flow-json"]').exists()).toBe(false);
    });

    it('says how many mistakes there are and shows them where they belong', async () => {
      const api = makeApi();
      api.validate.mockResolvedValue({
        data: {
          valid: false,
          errors: [
            {
              code: 'screen_title_required',
              path: 'screens.0.title',
              details: {},
            },
            {
              code: 'label_required',
              path: 'screens.0.blocks.1.label',
              details: {},
            },
          ],
          flow_json: null,
        },
      });
      const { wrapper } = await mountPage(sampleFlow(), api);

      expect(wrapper.find('[data-testid="flow-screen-errors"]').exists()).toBe(
        false
      );
      await wrapper.get('[data-testid="flow-editor-save"]').trigger('click');
      await flushPromises();
      expect(wrapper.get('[data-testid="flow-editor-state"]').text()).toContain(
        'ERRORS_COUNT'
      );
      expect(
        wrapper.get('[data-testid="flow-screen-errors"]').text()
      ).toContain('screen_title_required');
      await canvasBlocks(wrapper)[1].trigger('click');
      expect(wrapper.get('[data-testid="flow-block-props"]').text()).toContain(
        'label_required'
      );
    });
  });

  const newFlow = () => ({
    id: null,
    name: '',
    categories: [],
    definition: {
      schema_version: 1,
      screens: [{ title: 'Pantalla 1', button: '', blocks: [] }],
    },
  });
  const nameInput = wrapper =>
    wrapper.get('[data-testid="flow-editor-name"] input');
  const categorySelect = wrapper =>
    wrapper.findComponent('[data-testid="flow-category-select"]');
  const save = async wrapper => {
    await wrapper.get('[data-testid="flow-editor-save"]').trigger('click');
    await flushPromises();
  };
  const chooser = wrapper => wrapper.find('[data-testid="flow-starting"]');

  describe('the creation template never reappears', () => {
    it('hides blank validation until interaction and reveals only the touched field', async () => {
      const api = makeApi();
      api.validate.mockResolvedValue({
        data: {
          valid: false,
          flow_json: null,
          errors: [
            { code: 'button_required', path: 'screens.0.button', details: {} },
            { code: 'blocks_required', path: 'screens.0.blocks', details: {} },
          ],
        },
      });
      const { wrapper } = await mountPage(
        {
          ...newFlow(),
          name: 'Empty',
          definition: startingDefinition('blank'),
        },
        api
      );
      expect(wrapper.text()).not.toContain('ERRORS_COUNT');
      expect(wrapper.text()).not.toContain('button_required');
      expect(wrapper.text()).not.toContain('blocks_required');
      await wrapper
        .get('[data-testid="flow-screen-button"] input')
        .setValue(' ');
      expect(wrapper.text()).toContain('button_required');
      expect(wrapper.text()).not.toContain('blocks_required');
      await save(wrapper);
      expect(wrapper.text()).toContain('blocks_required');
    });
    it('keeps a truly empty screen without a chooser', async () => {
      const { wrapper } = await mountPage({
        ...newFlow(),
        definition: startingDefinition('blank'),
      });
      expect(chooser(wrapper).exists()).toBe(false);
      expect(tabs(wrapper)).toHaveLength(1);
      expect(canvasBlocks(wrapper)).toHaveLength(0);
      await wrapper.get('[data-testid="flow-add-heading"]').trigger('click');
      await wrapper.get('[data-testid="flow-canvas-remove"]').trigger('click');
      expect(chooser(wrapper).exists()).toBe(false);
    });
    it('loads the selected template directly', async () => {
      const { wrapper } = await mountPage({
        ...newFlow(),
        definition: startingDefinition('survey'),
      });
      expect(chooser(wrapper).exists()).toBe(false);
      expect(tabs(wrapper).length).toBeGreaterThan(1);
      expect(canvasBlocks(wrapper).length).toBeGreaterThan(0);
    });
  });

  describe('saving', () => {
    it('requires a name on save without requiring a category or another template choice', async () => {
      const { wrapper, api } = await mountPage(newFlow());
      expect(wrapper.find('[data-testid="flow-starting-error"]').exists()).toBe(
        false
      );

      await save(wrapper);

      expect(api.create).not.toHaveBeenCalled();
      const text = wrapper.get('[data-testid="flow-builder"]').text();
      expect(text).toContain('WHATSAPP_FLOWS.EDITOR.NAME_REQUIRED');
      expect(text).not.toContain('WHATSAPP_FLOWS.EDITOR.CATEGORY_REQUIRED');
      expect(wrapper.find('[data-testid="flow-starting-error"]').exists()).toBe(
        false
      );
      expect(
        wrapper.get('[data-testid="flow-editor-save"]').attributes('disabled')
      ).toBeUndefined();
    });

    it('clears each mark once that field is filled', async () => {
      const { wrapper } = await mountPage(newFlow());
      await save(wrapper);

      await nameInput(wrapper).setValue('Datos');
      categorySelect(wrapper).vm.$emit('update:modelValue', ['SURVEY']);
      await wrapper.vm.$nextTick();

      const text = wrapper.get('[data-testid="flow-builder"]').text();
      expect(text).not.toContain('NAME_REQUIRED');
      expect(text).not.toContain('CATEGORY_REQUIRED');
      expect(text).not.toContain('START_REQUIRED');
    });

    it('saves a new flow with its name, [category] and definition, then updates it', async () => {
      const { wrapper, api } = await mountPage({
        ...newFlow(),
        definition: startingDefinition('survey'),
      });
      await nameInput(wrapper).setValue('Datos');
      categorySelect(wrapper).vm.$emit('update:modelValue', [
        'LEAD_GENERATION',
      ]);
      await wrapper.vm.$nextTick();

      await save(wrapper);

      const [payload] = api.create.mock.calls[0];
      expect(payload).toMatchObject({
        name: 'Datos',
        categories: ['LEAD_GENERATION'],
      });
      expect(payload.definition.screens.length).toBeGreaterThan(1);
      expect(wrapper.emitted('saved')[0][0]).toMatchObject({ id: 9 });

      await nameInput(wrapper).setValue('Datos 2');
      await save(wrapper);

      expect(api.update).toHaveBeenCalledWith(
        9,
        expect.objectContaining({ name: 'Datos 2' })
      );
    });

    it('saves a saved flow without changes (the button is never disabled for that)', async () => {
      const { wrapper, api } = await mountPage();

      await save(wrapper);

      expect(api.update).toHaveBeenCalledWith(7, expect.any(Object));
    });

    it('defaults an empty category array to OTHER on save', async () => {
      const { wrapper, api } = await mountPage(sampleFlow({ categories: [] }));

      await save(wrapper);

      expect(api.update).toHaveBeenCalledWith(
        7,
        expect.objectContaining({ categories: ['OTHER'] })
      );
    });

    it('edits multiple categories and exports the chosen array unchanged', async () => {
      const { wrapper, api } = await mountPage(
        sampleFlow({ categories: ['LEAD_GENERATION', 'SURVEY', 'OTHER'] })
      );
      expect(categorySelect(wrapper).props('modelValue')).toEqual([
        'LEAD_GENERATION',
        'SURVEY',
        'OTHER',
      ]);

      categorySelect(wrapper).vm.$emit('update:modelValue', [
        'SURVEY',
        'OTHER',
      ]);
      await wrapper.vm.$nextTick();
      await save(wrapper);

      expect(api.update.mock.calls[0][1].categories).toEqual([
        'SURVEY',
        'OTHER',
      ]);
    });

    it('goes back', async () => {
      const { wrapper } = await mountPage();

      await wrapper.get('[data-testid="flow-editor-back"]').trigger('click');

      expect(wrapper.emitted('back')).toHaveLength(1);
    });
  });

  describe('publishing to Meta and testing', () => {
    const waba = { waba_id: '111', channel_id: 7, phone_number: '+593990001' };
    const metaApi = (publications = []) => ({
      ...makeApi(),
      publicationStatus: vi.fn().mockResolvedValue({
        data: { flow_id: 9, wabas: [waba], publications },
      }),
      publish: vi.fn().mockResolvedValue({ data: {} }),
      retryPublication: vi.fn().mockResolvedValue({ data: {} }),
      test: vi.fn().mockResolvedValue({ data: { success: true } }),
    });
    const saved = () => sampleFlow({ id: 9 });

    it('shows no Publicar, Probar or status for an account without a Cloud channel', async () => {
      const api = metaApi();
      api.publicationStatus.mockResolvedValue({
        data: { flow_id: 9, wabas: [], publications: [] },
      });
      const { wrapper } = await mountPage(saved(), api);

      expect(wrapper.find('[data-testid="flow-publish-open"]').exists()).toBe(
        false
      );
      expect(wrapper.find('[data-testid="flow-test-open"]').exists()).toBe(
        false
      );
      expect(wrapper.find('[data-testid="flow-meta-status"]').exists()).toBe(
        false
      );
    });

    it('shows the Meta status per WABA in the editor', async () => {
      const { wrapper } = await mountPage(
        saved(),
        metaApi([{ waba_id: '111', status: 'published', meta_flow_id: 'm1' }])
      );

      await wrapper.get('[data-testid="flow-editor-status"]').trigger('click');
      const badge = wrapper.get('[data-testid="flow-meta-badge"]');
      expect(badge.attributes('data-state')).toBe('published');
    });

    it('surfaces a failed publication in the compact status chip', async () => {
      const { wrapper } = await mountPage(
        saved(),
        metaApi([
          {
            waba_id: '111',
            status: 'draft',
            validation_errors: [{ message: 'Fix a field' }],
          },
        ])
      );
      expect(wrapper.get('[data-testid="flow-editor-status"]').text()).toBe(
        'WHATSAPP_FLOWS.META.STATE.error'
      );
      expect(wrapper.find('[data-testid="flow-meta-errors"]').exists()).toBe(
        false
      );
      await wrapper.get('[data-testid="flow-editor-status"]').trigger('click');
      expect(wrapper.get('[data-testid="flow-meta-errors"]').text()).toContain(
        'Fix a field'
      );
    });

    it('does not offer Publicar or Probar until the flow is saved and has no mistakes', async () => {
      const { wrapper, api } = await mountPage(
        sampleFlow({ id: null }),
        metaApi()
      );
      // a new flow has no WABAs to show until it is saved
      expect(api.publicationStatus).not.toHaveBeenCalled();

      await wrapper.get('[data-testid="flow-editor-save"]').trigger('click');
      await flushPromises();
      const publish = () => wrapper.get('[data-testid="flow-publish-open"]');
      expect(publish().attributes('disabled')).toBeUndefined();

      await wrapper
        .get('[data-testid="flow-editor-name"] input')
        .setValue('Otro');
      expect(publish().attributes('disabled')).toBeDefined();
      // the tooltip says why: save first
      expect(publish().attributes('title')).toBe(
        'WHATSAPP_FLOWS.META.SAVE_FIRST'
      );
      await wrapper.get('[data-testid="flow-actions"]').trigger('click');
      expect(
        wrapper.get('[data-testid="flow-test-open"]').attributes('disabled')
      ).toBeDefined();

      // saving brings it back
      await wrapper.get('[data-testid="flow-editor-save"]').trigger('click');
      await flushPromises();
      expect(publish().attributes('disabled')).toBeUndefined();
      expect(publish().attributes('title')).toBeFalsy();
    });

    it('blocks Publicar with a tooltip while the flow has mistakes of its own', async () => {
      const api = metaApi();
      api.validate.mockResolvedValue({
        data: {
          valid: false,
          errors: [{ code: 'form_empty' }],
          flow_json: null,
        },
      });
      const { wrapper } = await mountPage(saved(), api);

      const publish = wrapper.get('[data-testid="flow-publish-open"]');
      expect(publish.attributes('disabled')).toBeDefined();
      expect(publish.attributes('title')).toBe('WHATSAPP_FLOWS.META.FIX_FIRST');
    });

    it('asks, then publishes and shows the result without leaving the page', async () => {
      const { wrapper, api } = await mountPage(saved(), metaApi());

      await wrapper.get('[data-testid="flow-publish-open"]').trigger('click');
      await flushPromises();
      expect(api.publish).not.toHaveBeenCalled();
      await wrapper
        .get('[data-testid="flow-publish-confirm-button"]')
        .trigger('click');
      await flushPromises();

      expect(api.publish).toHaveBeenCalledWith(9);
      expect(
        wrapper.find('[data-testid="flow-publish-progress"]').exists()
      ).toBe(true);
    });

    it('retries a WABA that failed', async () => {
      const { wrapper, api } = await mountPage(
        saved(),
        metaApi([
          {
            waba_id: '111',
            status: 'draft',
            validation_errors: [{ error: 'X', message: 'bad value' }],
          },
        ])
      );

      await wrapper.get('[data-testid="flow-editor-status"]').trigger('click');
      expect(wrapper.get('[data-testid="flow-meta-errors"]').text()).toContain(
        'bad value'
      );
      await wrapper.get('[data-testid="flow-meta-retry"]').trigger('click');
      await flushPromises();

      expect(api.retryPublication).toHaveBeenCalledWith(9, '111');
    });

    it('sends a test through the chosen channel to the number', async () => {
      const { wrapper, api } = await mountPage(saved(), metaApi());

      await wrapper.get('[data-testid="flow-actions"]').trigger('click');
      await wrapper.get('[data-testid="flow-test-open"]').trigger('click');
      await flushPromises();
      await wrapper
        .get('[data-testid="flow-test-number"] input')
        .setValue('593991234567');
      await wrapper.get('[data-testid="flow-test-send"]').trigger('click');
      await flushPromises();

      expect(api.test).toHaveBeenCalledWith(9, {
        channelId: 7,
        phoneNumber: '593991234567',
      });
      expect(wrapper.find('[data-testid="flow-test-success"]').exists()).toBe(
        true
      );
    });
  });
});
