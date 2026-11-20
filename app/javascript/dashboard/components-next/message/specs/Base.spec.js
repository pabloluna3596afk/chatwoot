import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import Base from '../bubbles/Base.vue';

const context = {};
vi.mock('../provider.js', () => ({ useMessageContext: () => context }));

const render = (props = {}) =>
  mount(Base, {
    props,
    global: {
      stubs: {
        MessageMeta: {
          props: ['showTimestamp'],
          template:
            '<div data-meta :data-time="showTimestamp"><slot name="captain" /></div>',
        },
        CaptainGenerationDetails: {
          template: '<div data-captain><slot name="meta" /></div>',
        },
        ReplyPreview: true,
      },
    },
  });

describe('bubble metadata composition', () => {
  beforeEach(() =>
    Object.assign(context, {
      id: ref(9),
      variant: ref('agent'),
      orientation: ref('right'),
      inReplyTo: ref(null),
      shouldGroupWithNext: ref(false),
      contentAttributes: ref({}),
      sender: ref({ type: 'User' }),
    })
  );

  it('hides repeated time for ordinary intermediate messages', () => {
    context.shouldGroupWithNext.value = true;
    expect(render().find('[data-meta]').exists()).toBe(false);
  });

  it.each(['macro', 'automation', 'flow'])(
    'preserves %s on grouped messages',
    type => {
      context.shouldGroupWithNext.value = true;
      context.contentAttributes.value = { messageSource: { type, id: 2 } };
      const wrapper = render();
      expect(wrapper.get('[data-meta]').attributes('data-time')).toBe('false');
    }
  );

  it('mounts the existing Captain component with metadata on grouped replies', () => {
    context.shouldGroupWithNext.value = true;
    context.sender.value = { type: 'captain_assistant' };
    const wrapper = render();
    expect(wrapper.find('[data-captain] [data-meta]').exists()).toBe(true);
    expect(wrapper.get('[data-meta]').attributes('data-time')).toBe('false');
  });

  it('preserves the private handoff note and its details', () => {
    context.variant.value = 'private';
    context.contentAttributes.value = { captainHandoff: {} };
    const wrapper = render();
    expect(wrapper.classes()).toContain('bg-n-solid-amber');
    expect(wrapper.find('[data-captain]').exists()).toBe(true);
  });

  it('keeps the email spacing and the media overlay', () => {
    context.variant.value = 'email';
    const wrapper = render({ overlayMeta: true });
    const meta = wrapper.get('[data-meta]');
    expect(meta.classes()).toEqual(
      expect.arrayContaining([
        'px-3',
        'pb-3',
        'media-meta',
        'end-2',
        'text-white',
      ])
    );
  });

  it('does not create a meta row for activities or an explicit hideMeta', async () => {
    const wrapper = render({ hideMeta: true });
    expect(wrapper.find('[data-meta]').exists()).toBe(false);
    context.variant.value = 'activity';
    await wrapper.setProps({ hideMeta: false });
    expect(wrapper.find('[data-meta]').exists()).toBe(false);
  });
});
