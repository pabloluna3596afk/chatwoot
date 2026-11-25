import { useStore } from 'dashboard/composables/store';

// const { track, update } = useBackgroundTasks();
// track({ id: 'import:42', kind: 'import', title: 'Contacts', status: 'running' });
// update({ id: 'import:42', kind: 'import', title: 'Contacts', status: 'success' });
export const useBackgroundTasks = () => {
  const store = useStore();
  return {
    track: task => store.dispatch('backgroundTasks/track', task),
    update: task => store.dispatch('backgroundTasks/upsert', task),
  };
};
