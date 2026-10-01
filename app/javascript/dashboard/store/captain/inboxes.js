import CaptainInboxes from 'dashboard/api/captain/inboxes';
import { createStore } from '../storeFactory';
import { throwErrorMessage } from 'dashboard/store/utils/api';

export default createStore({
  name: 'CaptainInbox',
  API: CaptainInboxes,
  actions: mutations => ({
    setAppointments: async function setAppointments(
      { commit },
      { assistantId, inboxId, appointmentsEnabled }
    ) {
      commit(mutations.SET_UI_FLAG, { updatingItem: true });
      try {
        const { data } = await CaptainInboxes.updateAppointments({
          assistantId,
          inboxId,
          appointmentsEnabled,
        });
        commit(mutations.EDIT, data);
        commit(mutations.SET_UI_FLAG, { updatingItem: false });
        return data;
      } catch (error) {
        commit(mutations.SET_UI_FLAG, { updatingItem: false });
        return throwErrorMessage(error);
      }
    },
    delete: async function remove({ commit }, { inboxId, assistantId }) {
      commit(mutations.SET_UI_FLAG, { deletingItem: true });
      try {
        await CaptainInboxes.delete({ inboxId, assistantId });
        commit(mutations.DELETE, inboxId);
        commit(mutations.SET_UI_FLAG, { deletingItem: false });
        return inboxId;
      } catch (error) {
        commit(mutations.SET_UI_FLAG, { deletingItem: false });
        return throwErrorMessage(error);
      }
    },
  }),
});
