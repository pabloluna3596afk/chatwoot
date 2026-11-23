/* eslint no-param-reassign: 0 */
import CalendarAPI from 'dashboard/api/integrations/calendar';

export default {
  namespaced: true,
  state: () => ({ byAccount: {} }),
  getters: {
    hasGoogleConnection: state => accountId =>
      (state.byAccount[accountId] || []).some(
        item => item.provider === 'google'
      ),
  },
  mutations: {
    set(state, { accountId, connections }) {
      state.byAccount[accountId] = connections;
    },
  },
  actions: {
    async get({ commit }, accountId) {
      // The endpoint returns only active connections for the current account.
      const { data } = await CalendarAPI.getConnections();
      commit('set', { accountId, connections: data.payload });
      return data;
    },
  },
};
