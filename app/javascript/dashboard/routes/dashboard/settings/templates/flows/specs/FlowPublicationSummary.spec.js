import { mount } from '@vue/test-utils';
import FlowPublicationSummary from '../FlowPublicationSummary.vue';
import { withFullI18n } from 'test-i18n';
withFullI18n();

describe('FlowPublicationSummary', () => {
  it.each([
    [
      { state: 'published', published: 120, total: 120, errors: 0 },
      'Published · 120 of 120',
    ],
    [
      { state: 'partial', published: 108, total: 120, errors: 0 },
      'Partial · 108 of 120',
    ],
    [
      { state: 'error', published: 108, total: 120, errors: 2 },
      'With errors · 2',
    ],
    [{ state: 'none', published: 0, total: 120, errors: 0 }, 'Not sent'],
  ])(
    'shows one worst-state summary, without numbers or retired badges',
    async (summary, label) => {
      const wrapper = mount(FlowPublicationSummary, { props: { summary } });
      expect(wrapper.text()).toBe(label);
      expect(wrapper.findAll('button')).toHaveLength(1);
      await wrapper.get('button').trigger('click');
      expect(wrapper.emitted('details')).toHaveLength(1);
    }
  );
});
