export default {
  namespaced: true,
  state: () => ({ tasks: {}, order: [], loading: false, failed: false }),
  getters: {
    ordered: state => state.order.map(id => state.tasks[id]).filter(Boolean),
  },
  mutations: {
    upsert(state, task) {
      const previous = state.tasks[task.id];
      if (!previous || previous.status !== task.status) {
        state.order = [task.id, ...state.order.filter(id => id !== task.id)];
      }
      state.tasks[task.id] = task;
      const results = state.order.filter(
        id => state.tasks[id]?.status !== 'running'
      );
      results.slice(20).forEach(id => {
        delete state.tasks[id];
        state.order = state.order.filter(taskId => taskId !== id);
      });
    },
    dismiss(state, id) {
      delete state.tasks[id];
      state.order = state.order.filter(taskId => taskId !== id);
    },
    reset(state) {
      state.tasks = {};
      state.order = [];
      state.failed = false;
      state.loading = false;
    },
    setLoading(state, value) {
      state.loading = value;
    },
    setFailed(state, value) {
      state.failed = value;
    },
  },
  actions: {
    track({ state, dispatch }, task) {
      if (!state.tasks[task.id]) return dispatch('upsert', task);
      return undefined;
    },
    upsert({ commit }, task) {
      commit('upsert', task);
    },
    dismiss({ commit }, id) {
      commit('dismiss', id);
    },
    reset({ commit }) {
      commit('reset');
    },
  },
};
