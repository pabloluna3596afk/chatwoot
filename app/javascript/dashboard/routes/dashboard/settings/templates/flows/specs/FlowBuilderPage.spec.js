import { flushPromises, mount } from '@vue/test-utils';
import FlowBuilderPage from '../FlowBuilderPage.vue';
import FlowPhoneCanvas from '../FlowPhoneCanvas.vue';
import Draggable from 'vuedraggable';

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
  id: null,
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
    global: { mocks: { $t: key => key }, stubs: { Dialog: DialogStub } },
  });
  await flushPromises();
  return { wrapper, api };
};

const tabs = wrapper => wrapper.findAll('[data-testid="flow-screen-tab"]');
const canvasBlocks = wrapper =>
  wrapper.findAll('[data-testid="flow-canvas-block"]');

describe('FlowBuilderPage', () => {
  describe('screens as tabs above the phone', () => {
    it('has a tab per screen and the "+ Pantalla" tab at the end of the row', async () => {
      const { wrapper } = await mountPage();

      expect(tabs(wrapper)).toHaveLength(2);
      expect(tabs(wrapper)[0].text()).toContain('Tus datos');
      expect(tabs(wrapper)[0].text()).toContain('"n":1');
      const row = wrapper.get('[data-testid="flow-screen-tabs"]');
      expect(row.element.lastElementChild.getAttribute('data-testid')).toBe(
        'flow-screen-add'
      );
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

    it('lays the block buttons out in two columns from 960px up', async () => {
      const { wrapper } = await mountPage();

      const group = wrapper.get('[data-testid="flow-palette"] > div');
      expect(group.classes()).toContain('min-[960px]:grid-cols-2');
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
    it('has the name, a status chip and the "JSON de Meta" and "Guardar" buttons, and no channel choice', async () => {
      const { wrapper } = await mountPage();

      expect(
        wrapper.get('[data-testid="flow-editor-name"] input').element.value
      ).toBe('Datos');
      expect(wrapper.find('[data-testid="flow-editor-status"]').exists()).toBe(
        true
      );
      expect(wrapper.get('[data-testid="flow-json-toggle"]').text()).toBe(
        'WHATSAPP_FLOWS.EDITOR.SHOW_JSON'
      );
      expect(wrapper.find('[data-testid="flow-json"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="flow-editor-save"]').exists()).toBe(
        true
      );
      expect(wrapper.find('input[type="checkbox"]').exists()).toBe(false);
      expect(wrapper.find('select').exists()).toBe(false);
    });

    it('opens the JSON Meta will get in a modal, not inside the page', async () => {
      const { wrapper } = await mountPage();
      expect(wrapper.find('[data-testid="flow-json"]').exists()).toBe(false);

      await wrapper.get('[data-testid="flow-json-toggle"]').trigger('click');

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

  describe('saving', () => {
    it('saves a new flow with its name, categories and definition, then updates it', async () => {
      const { wrapper, api } = await mountPage();

      await wrapper.get('[data-testid="flow-editor-save"]').trigger('click');
      await flushPromises();

      const [payload] = api.create.mock.calls[0];
      expect(payload).toMatchObject({
        name: 'Datos',
        categories: ['LEAD_GENERATION'],
      });
      expect(payload.definition.screens).toHaveLength(2);
      expect(wrapper.emitted('saved')[0][0]).toMatchObject({ id: 9 });

      await wrapper
        .get('[data-testid="flow-editor-name"] input')
        .setValue('Datos 2');
      await wrapper.get('[data-testid="flow-editor-save"]').trigger('click');
      await flushPromises();

      expect(api.update).toHaveBeenCalledWith(
        9,
        expect.objectContaining({ name: 'Datos 2' })
      );
    });

    it('does not save without a name', async () => {
      const { wrapper, api } = await mountPage(sampleFlow({ name: '' }));

      await wrapper.get('[data-testid="flow-editor-save"]').trigger('click');

      expect(api.create).not.toHaveBeenCalled();
    });

    it('has no categories in the right column, only behind "Detalles del flow"', async () => {
      const { wrapper } = await mountPage();

      expect(
        wrapper.get('[data-testid="flow-properties"]').text()
      ).not.toContain('WHATSAPP_FLOWS.EDITOR.CATEGORIES');
      expect(
        wrapper.find('[data-testid="flow-category-LEAD_GENERATION"]').exists()
      ).toBe(false);
    });

    it('changes the categories in the "Detalles del flow" modal', async () => {
      const { wrapper, api } = await mountPage();

      await wrapper.get('[data-testid="flow-details-open"]').trigger('click');
      const modal = wrapper.get('[data-testid="flow-details-dialog"]');
      expect(
        modal.findAll('button[data-testid^="flow-category-"]')
      ).not.toHaveLength(0);
      await modal
        .findAll('button[data-testid^="flow-category-"]')[1]
        .trigger('click');
      await wrapper.get('[data-testid="flow-editor-save"]').trigger('click');
      await flushPromises();

      expect(api.create.mock.calls[0][0].categories).toHaveLength(2);
    });

    it('goes back', async () => {
      const { wrapper } = await mountPage();

      await wrapper.get('[data-testid="flow-editor-back"]').trigger('click');

      expect(wrapper.emitted('back')).toHaveLength(1);
    });
  });
});
