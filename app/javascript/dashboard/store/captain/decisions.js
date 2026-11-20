import API from 'dashboard/api/captain/decisions';
import camelcaseKeys from 'camelcase-keys';

// Account-scoped keys prevent reuse across accounts. Re-fetch on each opening:
// afterwards, permissions and completion reviews can change after a response.
export const decisionKey = ({ accountId, conversationId, messageId }) =>
  `${accountId}:${conversationId}:${messageId}`;

export default {
  namespaced: true,
  state: { entries: {} },
  getters: {
    getEntry: state => lookup => state.entries[decisionKey(lookup)],
  },
  actions: {
    async fetch({ state, commit }, lookup) {
      const key = decisionKey(lookup);
      if (state.entries[key]?.loading) return;
      commit('SET_ENTRY', { key, entry: { loading: true, error: null } });
      try {
        const { data } = await API.getForMessage(
          lookup.conversationId,
          lookup.messageId
        );
        commit('SET_ENTRY', {
          key,
          entry: {
            loading: false,
            error: null,
            decisions: camelcaseKeys(data, { deep: true }),
          },
        });
      } catch (error) {
        commit('SET_ENTRY', {
          key,
          entry: {
            loading: false,
            error: [401, 403].includes(error.response?.status)
              ? 'forbidden'
              : 'network',
          },
        });
      }
    },
  },
  mutations: {
    SET_ENTRY(state, { key, entry }) {
      state.entries = { ...state.entries, [key]: entry };
    },
  },
};
