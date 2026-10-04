import { mount } from '@vue/test-utils';
import TemplateCard from '../TemplateCard.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, te: () => false }),
}));

const template = {
  id: '555',
  name: 'recordatorio_cita',
  language: 'es',
  status: 'REJECTED',
  components: [{ type: 'BODY', text: 'Hola' }],
  inboxes: [{ id: 1, name: 'Soporte' }],
  inboxNames: 'Soporte',
};

const mountCard = props =>
  mount(TemplateCard, {
    props: { template, ...props },
    global: {
      mocks: { $t: key => key },
      directives: { tooltip: {} },
      stubs: { ChannelIcon: true },
    },
  });

describe('TemplateCard', () => {
  it('shows the category Meta assigned', () => {
    expect(mountCard().find('[data-testid="template-category"]').exists()).toBe(
      false
    );
    const wrapper = mountCard({
      template: { ...template, category: 'MARKETING' },
    });

    expect(wrapper.get('[data-testid="template-category"]').text()).toContain(
      'Marketing'
    );
  });

  it('shows no edit or delete button to someone who cannot manage templates', () => {
    const wrapper = mountCard();

    expect(wrapper.find('[data-testid="template-edit"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="template-delete"]').exists()).toBe(
      false
    );
  });

  it('shows edit and delete to an administrator and tells the page which one was pressed', async () => {
    const wrapper = mountCard({ canManage: true, canEdit: true });

    await wrapper.get('[data-testid="template-edit"]').trigger('click');
    await wrapper.get('[data-testid="template-delete"]').trigger('click');

    expect(wrapper.emitted('edit')).toHaveLength(1);
    expect(wrapper.emitted('delete')).toHaveLength(1);
    expect(wrapper.emitted('preview')).toBeUndefined();
  });

  it('offers only delete when the form cannot express the template', () => {
    const wrapper = mountCard({ canManage: true, canEdit: false });

    expect(wrapper.find('[data-testid="template-edit"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="template-delete"]').exists()).toBe(true);
  });
});
