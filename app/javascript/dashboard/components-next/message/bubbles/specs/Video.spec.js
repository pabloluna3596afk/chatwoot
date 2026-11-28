import { shallowMount } from '@vue/test-utils';
import { ref } from 'vue';
import Video from '../Video.vue';

vi.mock('../../provider.js', () => ({
  useMessageContext: () => ({
    attachments: ref([{ fileType: 'video', dataUrl: '/vertical.mp4' }]),
    filteredCurrentChatAttachments: ref([]),
  }),
}));

describe('video bubble', () => {
  it('limits vertical video height while preserving native proportions and controls', () => {
    const wrapper = shallowMount(Video, {
      global: { stubs: { BaseBubble: { template: '<div><slot /></div>' } } },
    });
    const video = wrapper.get('video');
    expect(video.classes()).toContain('max-h-[min(24rem,40vh)]');
    expect(video.classes()).toContain('w-auto');
    expect(video.attributes()).toHaveProperty('controls');
  });
});
