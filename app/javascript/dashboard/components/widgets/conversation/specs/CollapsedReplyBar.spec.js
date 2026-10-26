import { mount } from '@vue/test-utils';
import { REPLY_EDITOR_MODES } from 'dashboard/components/widgets/WootWriter/constants';
import CollapsedReplyBar from '../CollapsedReplyBar.vue';

const mountComponent = props =>
  mount(CollapsedReplyBar, {
    props: { replyLabel: 'Reply', ...props },
    global: { stubs: { Icon: true } },
  });

describe('CollapsedReplyBar', () => {
  it('offers reply and private note actions', () => {
    const wrapper = mountComponent();

    expect(wrapper.text()).toContain('Reply');
    expect(wrapper.text()).toContain('CONVERSATION.REPLYBOX.PRIVATE_NOTE');
  });

  it('opens the editor in the selected mode', async () => {
    const wrapper = mountComponent();
    const reply = wrapper
      .findAll('button')
      .find(button => button.text().includes('Reply'));
    const note = wrapper
      .findAll('button')
      .find(button =>
        button.text().includes('CONVERSATION.REPLYBOX.PRIVATE_NOTE')
      );

    await reply.trigger('click');
    await note.trigger('click');

    expect(wrapper.emitted('open')).toEqual([
      [REPLY_EDITOR_MODES.REPLY],
      [REPLY_EDITOR_MODES.NOTE],
    ]);
  });

  it('offers only a private note when public replies are restricted', () => {
    const wrapper = mountComponent({ canReply: false });

    expect(wrapper.text()).not.toContain('Reply');
    expect(wrapper.text()).toContain('CONVERSATION.REPLYBOX.PRIVATE_NOTE');
  });
});
