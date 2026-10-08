import { ref } from 'vue';

// Retained across send-dialog instances for the current dashboard session.
export const lastSendCenterTab = ref(0);
