import { computed, onBeforeUnmount, ref } from 'vue';

// What Meta says about a flow, one row per WhatsApp Cloud WABA of the account (two numbers on the same WABA share it).
// Publishing runs in the background, so after asking for it the status is polled until every WABA has its answer.
export const POLL_INTERVAL = 2000;
// A published flow that did not change is skipped by the job without touching its row, so there is nothing to see
// change: after this many polls an unchanged final row counts as the answer.
const SETTLE_POLLS = 4;
const MAX_POLLS = 60;

const FINAL_STATUSES = ['published', 'deprecated', 'blocked', 'throttled'];

export const errorLines = errors =>
  (errors || []).map(error => ({
    path: error.pointers?.[0]?.path || error.path || '',
    message: error.message || error.error || '',
  }));

// state: none (never sent) | draft | published | deprecated | error | blocked | throttled
export const buildRow = (waba, publication) => {
  const errors = errorLines(publication?.validation_errors);
  let state = publication?.status || 'none';
  if (errors.length && ['draft', 'published'].includes(state)) state = 'error';
  return {
    wabaId: waba.waba_id,
    channelId: waba.channel_id,
    phoneNumber: waba.phone_number,
    inboxName: waba.inbox_name || '',
    state,
    metaFlowId: publication?.meta_flow_id || null,
    errors,
    signature: JSON.stringify([
      publication?.status,
      publication?.published_at,
      publication?.meta_flow_id,
      publication?.validation_errors,
    ]),
  };
};

const isFinal = row =>
  row.state === 'error' || FINAL_STATUSES.includes(row.state);

export function useFlowPublications(api, getFlowId) {
  const wabas = ref([]);
  const unpublishedChanges = ref(null);
  const publications = ref([]);
  const isLoading = ref(false);
  const isPublishing = ref(false);
  const loadFailed = ref(false);

  let timer = null;
  let polls = 0;
  let before = {};

  const rows = computed(() =>
    wabas.value.map(waba =>
      buildRow(
        waba,
        publications.value.find(item => item.waba_id === waba.waba_id)
      )
    )
  );
  const hasCloud = computed(() => wabas.value.length > 0);

  const stop = () => {
    clearTimeout(timer);
    timer = null;
    isPublishing.value = false;
  };

  const load = async () => {
    const id = getFlowId();
    if (!id) return false;
    isLoading.value = true;
    try {
      const { data } = await api.publicationStatus(id);
      wabas.value = data.wabas || [];
      unpublishedChanges.value = data.unpublished_changes;
      publications.value = data.publications || [];
      loadFailed.value = false;
      return true;
    } catch {
      loadFailed.value = true;
      return false;
    } finally {
      isLoading.value = false;
    }
  };

  const settled = () =>
    rows.value.length > 0 &&
    rows.value.every(
      row =>
        isFinal(row) &&
        (row.signature !== before[row.wabaId] || polls >= SETTLE_POLLS)
    );

  const poll = async () => {
    polls += 1;
    const ok = await load();
    if (!ok || settled() || polls >= MAX_POLLS) {
      stop();
      return;
    }
    timer = setTimeout(poll, POLL_INTERVAL);
  };

  const follow = () => {
    before = Object.fromEntries(
      rows.value.map(row => [row.wabaId, row.signature])
    );
    polls = 0;
    isPublishing.value = true;
    clearTimeout(timer);
    timer = setTimeout(poll, POLL_INTERVAL);
  };

  // Asks for the publication and follows it; the caller handles the request being refused (it throws).
  const publish = async () => {
    await api.publish(getFlowId());
    follow();
  };

  const retry = async wabaId => {
    await api.retryPublication(getFlowId(), wabaId);
    follow();
  };

  onBeforeUnmount(stop);

  return {
    rows,
    unpublishedChanges,
    wabas,
    hasCloud,
    isLoading,
    isPublishing,
    loadFailed,
    load,
    publish,
    retry,
    stop,
  };
}
