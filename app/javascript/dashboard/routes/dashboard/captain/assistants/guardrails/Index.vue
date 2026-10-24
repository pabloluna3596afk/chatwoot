<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { picoSearch } from '@chatwoot/pico-search';
import { useStore } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAssistantSettings } from '../settings/useAssistantSettings';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

import SettingsPageLayout from 'dashboard/components-next/captain/pageComponents/assistant/settings/SettingsPageLayout.vue';
import SuggestedRules from 'dashboard/components-next/captain/assistant/SuggestedRules.vue';
import AddNewRulesInput from 'dashboard/components-next/captain/assistant/AddNewRulesInput.vue';
import AddNewRulesDialog from 'dashboard/components-next/captain/assistant/AddNewRulesDialog.vue';
import RuleCard from 'dashboard/components-next/captain/assistant/RuleCard.vue';
import BulkSelectBar from 'dashboard/components-next/captain/assistant/BulkSelectBar.vue';

const { t } = useI18n();
const store = useStore();
const { uiSettings, updateUISettings } = useUISettings();
const { assistantId, assistant } = useAssistantSettings();

const searchQuery = ref('');
const isSaving = ref(false);
const saveError = ref('');
const deleteDialog = ref(null);
const deleteIds = ref([]);

const requestDelete = ids => {
  if (isSaving.value) return;
  deleteIds.value = [...ids];
  deleteDialog.value.open();
};
const newInlineRule = ref('');
const newDialogRule = ref('');

// Keep the list the editor was opened with, even if another consumer refreshes the store.
const originalRules = ref(null);
watch(
  [assistantId, () => assistant.value?.guardrails],
  ([id, rules], [previousId] = []) => {
    if (id !== previousId || originalRules.value === null) {
      originalRules.value = rules ? [...rules] : null;
    }
  },
  { immediate: true }
);
const guardrailsContent = computed(() => originalRules.value || []);

const displayGuardrails = computed(() =>
  guardrailsContent.value.map((c, idx) => ({ id: idx, content: c }))
);

const guardrailsExample = [
  {
    id: 1,
    content:
      'Block queries that share or request sensitive personal information (e.g. phone numbers, passwords).',
  },
  {
    id: 2,
    content:
      'Reject queries that include offensive, discriminatory, or threatening language.',
  },
  {
    id: 3,
    content:
      'Deflect when the assistant is asked for legal or medical diagnosis or treatment.',
  },
];

const filteredGuardrails = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return displayGuardrails.value;
  return picoSearch(displayGuardrails.value, query, ['content']);
});

const shouldShowSuggestedRules = computed(() => {
  return uiSettings.value?.show_guardrails_suggestions !== false;
});

const closeSuggestedRules = () => {
  updateUISettings({ show_guardrails_suggestions: false });
};

// Bulk selection & hover state
const bulkSelectedIds = ref(new Set());
const hoveredCard = ref(null);

watch(assistantId, () => {
  bulkSelectedIds.value = new Set();
  hoveredCard.value = null;
});

const handleRuleSelect = id => {
  const selected = new Set(bulkSelectedIds.value);
  selected[selected.has(id) ? 'delete' : 'add'](id);
  bulkSelectedIds.value = selected;
};

const handleRuleHover = (isHovered, id) => {
  hoveredCard.value = isHovered ? id : null;
};

const buildSelectedCountLabel = computed(() => {
  const count = displayGuardrails.value.length || 0;
  const isAllSelected = bulkSelectedIds.value.size === count && count > 0;
  return isAllSelected
    ? t('CAPTAIN.ASSISTANTS.GUARDRAILS.BULK_ACTION.UNSELECT_ALL', { count })
    : t('CAPTAIN.ASSISTANTS.GUARDRAILS.BULK_ACTION.SELECT_ALL', { count });
});

const selectedCountLabel = computed(() => {
  return t('CAPTAIN.ASSISTANTS.GUARDRAILS.BULK_ACTION.SELECTED', {
    count: bulkSelectedIds.value.size,
  });
});

const saveGuardrails = async list => {
  const targetAssistantId = assistantId.value;
  await store.dispatch('captainAssistants/update', {
    id: targetAssistantId,
    assistant: {
      guardrails: list,
      expected_guardrails: [...guardrailsContent.value],
    },
  });
  if (assistantId.value === targetAssistantId) originalRules.value = [...list];
};

const addGuardrail = async content => {
  if (isSaving.value) return false;
  isSaving.value = true;
  saveError.value = '';
  try {
    const newGuardrails = [...guardrailsContent.value, content];
    await saveGuardrails(newGuardrails);
    useAlert(t('CAPTAIN.ASSISTANTS.GUARDRAILS.API.ADD.SUCCESS'));
    return true;
  } catch (error) {
    saveError.value =
      error.message || t('CAPTAIN.ASSISTANTS.GUARDRAILS.API.ADD.ERROR');
    useAlert(saveError.value);
    return false;
  } finally {
    isSaving.value = false;
  }
};

const editGuardrail = async ({ id, content }) => {
  if (isSaving.value) return false;
  isSaving.value = true;
  saveError.value = '';
  try {
    const updated = [...guardrailsContent.value];
    updated[id] = content;
    await saveGuardrails(updated);
    useAlert(t('CAPTAIN.ASSISTANTS.GUARDRAILS.API.UPDATE.SUCCESS'));
    return true;
  } catch (error) {
    saveError.value =
      error.message || t('CAPTAIN.ASSISTANTS.GUARDRAILS.API.UPDATE.ERROR');
    useAlert(saveError.value);
    return false;
  } finally {
    isSaving.value = false;
  }
};

const bulkDeleteGuardrails = async () => {
  if (isSaving.value) return false;
  isSaving.value = true;
  saveError.value = '';
  try {
    if (deleteIds.value.length === 0) return false;
    const updated = guardrailsContent.value.filter(
      (_, idx) => !deleteIds.value.includes(idx)
    );
    await saveGuardrails(updated);
    bulkSelectedIds.value = new Set();
    deleteDialog.value.close();
    useAlert(t('CAPTAIN.ASSISTANTS.GUARDRAILS.API.DELETE.SUCCESS'));
    return true;
  } catch (error) {
    saveError.value =
      error.message || t('CAPTAIN.ASSISTANTS.GUARDRAILS.API.DELETE.ERROR');
    useAlert(saveError.value);
    return false;
  } finally {
    isSaving.value = false;
  }
};

const addAllExample = async () => {
  if (isSaving.value) return false;
  isSaving.value = true;
  saveError.value = '';
  try {
    const exampleContents = guardrailsExample.map(example => example.content);
    const newGuardrails = [...guardrailsContent.value, ...exampleContents];
    await saveGuardrails(newGuardrails);
    useAlert(t('CAPTAIN.ASSISTANTS.GUARDRAILS.API.ADD.SUCCESS'));
    return true;
  } catch (error) {
    saveError.value =
      error.message || t('CAPTAIN.ASSISTANTS.GUARDRAILS.API.ADD.ERROR');
    useAlert(saveError.value);
    return false;
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <SettingsPageLayout
    :heading="t('CAPTAIN.ASSISTANTS.GUARDRAILS.TITLE')"
    :description="t('CAPTAIN.ASSISTANTS.GUARDRAILS.DESCRIPTION')"
  >
    <p v-if="saveError" role="alert" class="text-sm text-n-ruby-11">
      {{ saveError }}
    </p>
    <SuggestedRules
      v-if="shouldShowSuggestedRules"
      :title="t('CAPTAIN.ASSISTANTS.GUARDRAILS.ADD.SUGGESTED.TITLE')"
      :items="guardrailsExample"
      @add="addAllExample"
      @close="closeSuggestedRules"
    >
      <template #default="{ item }">
        <div class="flex items-center justify-between w-full">
          <span class="text-sm text-n-slate-12">
            {{ item.content }}
          </span>
          <Button
            :label="t('CAPTAIN.ASSISTANTS.GUARDRAILS.ADD.SUGGESTED.ADD_SINGLE')"
            ghost
            xs
            slate
            class="!text-sm !text-n-slate-11 flex-shrink-0"
            @click="addGuardrail(item.content)"
          />
        </div>
      </template>
    </SuggestedRules>
    <div class="flex flex-col gap-4">
      <div class="flex justify-between items-center">
        <BulkSelectBar
          v-model="bulkSelectedIds"
          :all-items="displayGuardrails"
          :select-all-label="buildSelectedCountLabel"
          :selected-count-label="selectedCountLabel"
          :delete-label="
            t('CAPTAIN.ASSISTANTS.GUARDRAILS.BULK_ACTION.BULK_DELETE_BUTTON')
          "
          @bulk-delete="requestDelete(bulkSelectedIds)"
        >
          <template #default-actions>
            <AddNewRulesDialog
              v-model="newDialogRule"
              :placeholder="
                t('CAPTAIN.ASSISTANTS.GUARDRAILS.ADD.NEW.PLACEHOLDER')
              "
              :button-label="t('CAPTAIN.ASSISTANTS.GUARDRAILS.ADD.NEW.TITLE')"
              :confirm-label="t('CAPTAIN.ASSISTANTS.GUARDRAILS.ADD.NEW.CREATE')"
              :cancel-label="t('CAPTAIN.ASSISTANTS.GUARDRAILS.ADD.NEW.CANCEL')"
              @add="addGuardrail"
            />
            <!-- Will enable this feature in future -->
            <!-- <div class="h-4 w-px bg-n-strong" />
            <Button
              :label="t('CAPTAIN.ASSISTANTS.GUARDRAILS.ADD.NEW.TEST_ALL')"
              xs
              ghost
              slate
              class="!text-sm"
            /> -->
          </template>
        </BulkSelectBar>
        <div
          v-if="displayGuardrails.length && bulkSelectedIds.size === 0"
          class="max-w-[22.5rem] w-full min-w-0"
        >
          <Input
            v-model="searchQuery"
            :placeholder="
              t('CAPTAIN.ASSISTANTS.GUARDRAILS.LIST.SEARCH_PLACEHOLDER')
            "
          />
        </div>
      </div>
      <div v-if="displayGuardrails.length === 0" class="mt-1 mb-2">
        <span class="text-n-slate-11 text-sm">
          {{ t('CAPTAIN.ASSISTANTS.GUARDRAILS.EMPTY_MESSAGE') }}
        </span>
      </div>
      <div v-else-if="filteredGuardrails.length === 0" class="mt-1 mb-2">
        <span class="text-n-slate-11 text-sm">
          {{ t('CAPTAIN.ASSISTANTS.GUARDRAILS.SEARCH_EMPTY_MESSAGE') }}
        </span>
      </div>
      <div v-else class="flex flex-col gap-2">
        <RuleCard
          v-for="guardrail in filteredGuardrails"
          :id="guardrail.id"
          :key="guardrail.id"
          :content="guardrail.content"
          :is-selected="bulkSelectedIds.has(guardrail.id)"
          :selectable="hoveredCard === guardrail.id || bulkSelectedIds.size > 0"
          @select="handleRuleSelect"
          @edit="editGuardrail"
          @delete="id => requestDelete([id])"
          @hover="isHovered => handleRuleHover(isHovered, guardrail.id)"
        />
      </div>
      <AddNewRulesInput
        v-model="newInlineRule"
        :placeholder="
          t('CAPTAIN.ASSISTANTS.GUARDRAILS.ADD.SUGGESTED.PLACEHOLDER')
        "
        :label="t('CAPTAIN.ASSISTANTS.GUARDRAILS.ADD.SUGGESTED.SAVE')"
        @add="addGuardrail"
      />
    </div>
    <Dialog
      ref="deleteDialog"
      type="alert"
      :title="t('CAPTAIN.PERSISTENCE.DELETE_TITLE')"
      :description="
        t('CAPTAIN.PERSISTENCE.DELETE_DESCRIPTION', { count: deleteIds.length })
      "
      :is-loading="isSaving"
      @confirm="bulkDeleteGuardrails"
    />
  </SettingsPageLayout>
</template>
