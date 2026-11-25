const SUCCESS_DURATION = 10000;
const timers = new WeakMap();

const clearTimer = (state, id) => {
  const pending = timers.get(state);
  clearTimeout(pending?.get(id));
  pending?.delete(id);
};

export default {
  namespaced: true,
  state: () => ({ tasks: {}, order: [] }),
  getters: {
    ordered: state =>
      state.order
        .map(id => state.tasks[id])
        .sort(
          (a, b) =>
            Number(a.status === 'running') - Number(b.status === 'running')
        ),
  },
  mutations: {
    upsert(state, task) {
      if (state.tasks[task.id]?.status !== task.status) {
        state.order = [task.id, ...state.order.filter(id => id !== task.id)];
      }
      state.tasks[task.id] = task;
    },
    dismiss(state, id) {
      delete state.tasks[id];
      state.order = state.order.filter(taskId => taskId !== id);
    },
    reset(state) {
      state.tasks = {};
      state.order = [];
    },
  },
  actions: {
    track({ state, dispatch }, task) {
      if (!state.tasks[task.id]) return dispatch('upsert', task);
      return undefined;
    },
    upsert({ state, commit, dispatch }, task) {
      clearTimer(state, task.id);
      commit('upsert', task);
      if (task.status === 'success') {
        if (!timers.has(state)) timers.set(state, new Map());
        timers.get(state).set(
          task.id,
          setTimeout(() => dispatch('dismiss', task.id), SUCCESS_DURATION)
        );
      }
    },
    dismiss({ state, commit }, id) {
      clearTimer(state, id);
      commit('dismiss', id);
    },
    reset({ state, commit }) {
      timers.get(state)?.forEach(clearTimeout);
      timers.delete(state);
      commit('reset');
    },
  },
};
