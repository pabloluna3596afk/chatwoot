import PlansAPI from 'dashboard/api/plans';

// Keep pending requests out of reactive state, isolated per store instance.
const requests = new WeakMap();

export default {
  namespaced: true,
  state: () => ({ accountId: null, records: [], status: 'idle', revision: 0 }),
  mutations: {
    activate(state, accountId) {
      if (state.accountId === accountId) return;
      state.accountId = accountId;
      state.records = [];
      state.status = 'idle';
      state.revision += 1;
    },
    setStatus(state, status) {
      state.status = status;
    },
    setRecords(state, records) {
      state.records = records;
      state.status = 'loaded';
    },
  },
  actions: {
    load({ state, commit }, { accountId, reload = false }) {
      commit('activate', accountId);
      const pending = requests.get(state);
      if (pending?.revision === state.revision) return pending.promise;
      if (!reload && state.status === 'loaded') return state.records;
      const { revision } = state;
      commit('setStatus', 'loading');
      const promise = PlansAPI.get(accountId)
        .then(({ data }) => {
          if (state.revision === revision) commit('setRecords', data);
          return data;
        })
        .catch(() => {
          if (state.revision === revision) commit('setStatus', 'error');
        })
        .finally(() => {
          if (requests.get(state)?.revision === revision)
            requests.delete(state);
        });
      requests.set(state, { revision, promise });
      return promise;
    },
  },
};
