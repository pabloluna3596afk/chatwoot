import CaptainAssistantAPI from 'dashboard/api/captain/assistant';
import { throwErrorMessage } from 'dashboard/store/utils/api';
import { createStore } from '../storeFactory';

export default createStore({
  name: 'CaptainAssistant',
  API: CaptainAssistantAPI,
  actions: mutations => ({
    updateAvatar: async ({ commit }, { id, file }) => {
      commit(mutations.SET_UI_FLAG, { updatingItem: true });
      try {
        const response = await CaptainAssistantAPI.updateAvatar(id, file);
        commit(mutations.EDIT, response.data);
        return response.data;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        commit(mutations.SET_UI_FLAG, { updatingItem: false });
      }
    },

    deleteAvatar: async ({ commit }, id) => {
      commit(mutations.SET_UI_FLAG, { updatingItem: true });
      try {
        const response = await CaptainAssistantAPI.deleteAvatar(id);
        commit(mutations.EDIT, response.data);
        return response.data;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        commit(mutations.SET_UI_FLAG, { updatingItem: false });
      }
    },
  }),
});
