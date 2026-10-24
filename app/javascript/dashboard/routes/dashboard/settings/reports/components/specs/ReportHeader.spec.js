import { mount } from '@vue/test-utils';
import ReportHeader from '../ReportHeader.vue';

vi.mock('dashboard/components/widgets/BackButton.vue', () => ({
  default: { template: '<button data-back>Back</button>' },
}));

describe('ReportHeader', () => {
  it('preserves long titles, descriptions, actions and optional back navigation', () => {
    const headerTitle =
      'Informe de rendimiento del equipo de atención al cliente';
    const wrapper = mount(ReportHeader, {
      props: {
        headerTitle,
        headerDescription: 'Description',
        hasBackButton: true,
      },
      slots: { default: '<button>Export</button>' },
    });
    expect(wrapper.text()).toContain(headerTitle);
    expect(wrapper.get('p').text()).toBe('Description');
    expect(wrapper.find('[data-back]').exists()).toBe(true);
    expect(wrapper.text()).toContain('Export');
  });
});
