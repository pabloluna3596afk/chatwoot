import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import LegacyCardLabels from '../conversationCardComponents/CardLabels.vue';
import CardLabels from 'next/Conversation/ConversationCard/CardLabels.vue';
import CardLabelsV5 from 'next/Conversation/ConversationCard/CardLabelsV5.vue';
import Label from 'dashboard/components/ui/Label.vue';
const push = vi.hoisted(() => vi.fn());
vi.mock('vue-router', () => ({
  useRouter: () => ({ push }),
}));
const label = { id: 1, title: 'cliente-con-un-nombre-largo', color: '#336699' };
describe('card label navigation', () => {
  it.each([LegacyCardLabels, CardLabels, CardLabelsV5])(
    'navigates by title without opening the card',
    async component => {
      const openCard = vi.fn();
      const wrapper = mount(component, {
        props: {
          conversationLabels: [label.title],
          labels: [label.title],
          accountLabels: [label],
        },
        attrs: { onClick: openCard },
        global: {
          plugins: [
            createStore({
              getters: {
                getCurrentAccountId: () => 1,
                'labels/getLabels': () => [label],
              },
            }),
          ],
          components: { 'woot-label': Label },
          directives: { resize: () => {} },
        },
      });
      const target = wrapper.find('[role="link"]').exists()
        ? wrapper.get('[role="link"]')
        : wrapper.get('button');
      await target.trigger('click');
      expect(push).toHaveBeenCalledWith({
        name: 'label_conversations',
        params: { accountId: 1, label: label.title },
      });
      expect(openCard).not.toHaveBeenCalled();
      expect(wrapper.find(`[title="${label.title}"]`).exists()).toBe(true);
      wrapper.unmount();
    }
  );
});
