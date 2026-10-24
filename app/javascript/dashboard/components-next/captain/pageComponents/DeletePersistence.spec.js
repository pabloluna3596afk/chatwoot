import { shallowMount } from '@vue/test-utils';
import DeleteDialog from './DeleteDialog.vue';
import BulkDeleteDialog from './BulkDeleteDialog.vue';
import ConfirmDeleteCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/ConfirmDeleteCampaignDialog.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const mocks = vi.hoisted(() => ({
  dispatch: vi.fn(),
  close: vi.fn(),
  alert: vi.fn(),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: mocks.dispatch }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: mocks.alert }));

beforeEach(() => vi.clearAllMocks());
describe.each([
  [
    DeleteDialog,
    { type: 'Assistants', translationKey: 'ASSISTANTS', entity: { id: 7 } },
  ],
  [BulkDeleteDialog, { type: 'AssistantResponse', bulkIds: new Set([1, 2]) }],
  [ConfirmDeleteCampaignDialog, { selectedCampaign: { id: 7 } }],
])('Destructive wrapper', (Component, props) => {
  it.each([new Error('Network error'), { response: { status: 422 } }])(
    'stays open on failure, retries and closes only on success',
    async error => {
      let reject;
      mocks.dispatch.mockImplementationOnce(
        () =>
          new Promise((_resolve, rejectRequest) => {
            reject = rejectRequest;
          })
      );
      const wrapper = shallowMount(Component, {
        props,
        global: {
          stubs: {
            Dialog: { methods: { close: mocks.close }, template: '<div />' },
          },
        },
      });
      const dialog = wrapper.findComponent(Dialog);
      dialog.vm.$emit('close');
      expect(mocks.dispatch).not.toHaveBeenCalled();
      const first = wrapper.vm.handleDialogConfirm();
      await wrapper.vm.handleDialogConfirm();
      expect(mocks.dispatch).toHaveBeenCalledOnce();
      expect(mocks.close).not.toHaveBeenCalled();
      reject(error);
      await first;
      expect(mocks.close).not.toHaveBeenCalled();
      expect(wrapper.emitted('deleteSuccess')).toBeUndefined();
      mocks.dispatch.mockResolvedValue(undefined);
      await wrapper.vm.handleDialogConfirm();
      expect(mocks.close).toHaveBeenCalledOnce();
      if (Component !== ConfirmDeleteCampaignDialog)
        expect(wrapper.emitted('deleteSuccess')).toHaveLength(1);
      wrapper.unmount();
    }
  );
});
