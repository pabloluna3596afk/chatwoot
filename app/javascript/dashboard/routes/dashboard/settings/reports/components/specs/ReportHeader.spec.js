import { mount } from '@vue/test-utils';
import ReportHeader from '../ReportHeader.vue';

vi.mock('dashboard/components/widgets/BackButton.vue', () => ({
  default: { template: '<button data-back>Back</button>' },
}));

describe('ReportHeader', () => {
  it('limits action sizing to CTAs and leaves nested download options alone', () => {
    const wrapper = mount(ReportHeader, {
      props: { headerTitle: 'Reports' },
      slots: {
        default: `<button data-cta>Export</button>
          <div><button data-cta>Download</button>
            <div><button class="py-2" data-format>CSV</button></div>
          </div>`,
      },
    });
    const actions = wrapper.get('[class*="sm:shrink-0"]');
    const selectors = actions
      .classes()
      .filter(name => name.endsWith(':!h-auto'))
      .map(name =>
        name
          .slice(1, name.indexOf(']'))
          .replaceAll('_', ' ')
          .replace('&', ':scope')
      );
    const sizedButtons = actions.element.querySelectorAll(selectors.join(','));
    expect([...sizedButtons]).toEqual(
      wrapper.findAll('[data-cta]').map(node => node.element)
    );
    expect(wrapper.get('[data-format]').classes()).toContain('py-2');
  });

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
