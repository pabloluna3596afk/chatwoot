import { ref } from 'vue';

export const seenActivity = ref({});
export const isActivityPanelOpen = ref(false);
export const activityIndicatorSnapshot = ref(null);

export const taskVersion = task =>
  String(task.version || task.updated_at || '0');

export const loadSeenActivity = key => {
  try {
    seenActivity.value = JSON.parse(localStorage.getItem(key) || '{}');
  } catch {
    seenActivity.value = {};
  }
};

export const persistSeenActivity = (key, value) => {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // The current session remains usable when browser storage is unavailable.
  }
};

export const isActivityTaskSeen = (key, task, sessionSeen = {}) => {
  try {
    const seen = JSON.parse(localStorage.getItem(key) || '{}');
    return (
      seen[task.id] === taskVersion(task) ||
      sessionSeen[task.id] === taskVersion(task)
    );
  } catch {
    return sessionSeen[task.id] === taskVersion(task);
  }
};
