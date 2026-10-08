import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import TemplatesTable from '../TemplatesTable.vue';
import TemplateRowActions from '../TemplateRowActions.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import en from 'dashboard/i18n/locale/en/whatsappTemplateMgmt.json';
import es from 'dashboard/i18n/locale/es/whatsappTemplateMgmt.json';

describe('shared templates table', () => {
  it('renders configurable columns and already paginated rows, with a range footer', async () => {
    const wrapper = mount(TemplatesTable, {
      props: {
        columns: [{ key: 'name', label: 'Nombre' }],
        items: [{ id: 11, name: 'Visible' }],
        total: 32,
        page: 2,
        pageSize: 10,
        perPageOptions: [10, 25, 50],
      },
      global: {
        plugins: [
          createI18n({ legacy: false, locale: 'es', messages: { es } }),
        ],
      },
    });
    expect(wrapper.findAll('tbody tr')).toHaveLength(1);
    expect(wrapper.text()).toContain('Nombre');
    expect(wrapper.text()).toContain('Visible');
    expect(wrapper.text()).toContain('11–20 de 32');
    const footer = wrapper.findComponent(PaginationFooter);
    footer.vm.$emit('update:currentPage', 3);
    footer.vm.$emit('update:itemsPerPage', 25);
    expect(wrapper.emitted('update:page')[0]).toEqual([3]);
    expect(wrapper.emitted('update:pageSize')[0]).toEqual([25]);
    expect(footer.props('perPageOptions')).toEqual([10, 25, 50]);
  });

  it('gives all three actions exactly the same Button props and emits distinct actions', async () => {
    const wrapper = mount(TemplateRowActions, {
      props: {
        canManage: true,
        canEdit: true,
        labels: {
          edit: 'Editar',
          duplicate: 'Duplicar',
          delete: 'Eliminar',
          view: 'Ver',
        },
      },
    });
    const buttons = wrapper.findAllComponents(Button);
    expect(buttons.map(button => button.props('icon'))).toEqual([
      'i-lucide-pencil',
      'i-lucide-copy',
      'i-lucide-trash',
    ]);
    await Promise.all(
      buttons.map(async button => {
        expect(button.props()).toMatchObject({
          variant: 'outline',
          color: 'slate',
          size: 'sm',
        });
        await button.trigger('click');
      })
    );
    ['edit', 'duplicate', 'delete'].forEach(action =>
      expect(wrapper.emitted(action)).toHaveLength(1)
    );
    expect(buttons[2].classes()).toContain('hover:enabled:text-n-ruby-11');
    expect(buttons[2].classes()).not.toContain('bg-n-ruby-9');
  });

  it('opens rows on click and Enter, without opening for action clicks', async () => {
    const wrapper = mount(TemplatesTable, {
      props: {
        columns: [{ key: 'name', label: 'Name' }],
        items: [{ id: 1, name: 'Test' }],
        total: 1,
        page: 1,
        pageSize: 10,
      },
      slots: { name: '<button @click.stop>Action</button>' },
    });
    const row = wrapper.get('tbody tr');
    await row.trigger('click');
    await row.trigger('keydown.enter');
    expect(wrapper.emitted('open')).toHaveLength(2);
    await row.get('button').trigger('click');
    expect(wrapper.emitted('open')).toHaveLength(2);
    wrapper.unmount();
  });

  it('keeps Spanish and English additions aligned and uses Bandeja', () => {
    const spanish = es.WHATSAPP_TEMPLATE_MGMT;
    const english = en.WHATSAPP_TEMPLATE_MGMT;
    expect(Object.keys(spanish.TABLE)).toEqual(Object.keys(english.TABLE));
    expect(Object.keys(spanish.FILTERS)).toEqual(Object.keys(english.FILTERS));
    expect(spanish.TABLE.INBOX).toBe('Bandeja');
    expect(spanish.FILTERS.ALL_INBOXES).toBe('Todas las bandejas');
  });
});
