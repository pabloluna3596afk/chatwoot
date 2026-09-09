<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

// Rendered from Message.content_attributes.suggestedAttributes, written by
// Panel AI on handoff (see human_handoff.py). Never writes anywhere on its
// own — every value here needs an agent's click. Chips with no matching
// attribute definition (hasField: false) show as informational only, since
// creating a custom attribute is an admin decision, not the agent's.
defineProps({
  suggestions: {
    type: Array,
    required: true,
  },
});

const { t } = useI18n();
const store = useStore();
const currentChat = useMapGetter('getSelectedChat');

// Local-only: not persisted on the message, so a page reload shows the chip
// as pending again. Re-applying just writes the same value again — harmless.
const appliedKeys = ref(new Set());
const pendingKeys = ref(new Set());

const chipKey = (suggestion, index) =>
  `${suggestion.target}:${suggestion.key || index}`;

const applySuggestion = async (suggestion, index) => {
  const key = chipKey(suggestion, index);
  if (appliedKeys.value.has(key) || pendingKeys.value.has(key)) return;

  pendingKeys.value.add(key);
  try {
    if (suggestion.target === 'contact') {
      await store.dispatch('contacts/update', {
        id: currentChat.value.contact_id,
        customAttributes: { [suggestion.key]: suggestion.value },
      });
    } else {
      // The conversation endpoint replaces the whole hash unless merged
      // client-side first (see ConversationCustomAttributesConcern#custom_attributes).
      const merged = {
        ...(currentChat.value.custom_attributes || {}),
        [suggestion.key]: suggestion.value,
      };
      await store.dispatch('conversation/updateCustomAttributes', {
        conversationId: currentChat.value.id,
        customAttributes: merged,
      });
    }
    appliedKeys.value.add(key);
  } catch (error) {
    useAlert(t('CONVERSATION.SUGGESTED_ATTRIBUTES.APPLY_ERROR'));
  } finally {
    pendingKeys.value.delete(key);
  }
};
</script>

<template>
  <div
    v-if="suggestions.length"
    class="flex flex-wrap gap-1.5 pt-1 border-t border-n-alpha-2"
  >
    <div
      v-for="(suggestion, index) in suggestions"
      :key="chipKey(suggestion, index)"
      class="flex items-center gap-1.5 px-2 py-1 rounded-full text-xs"
      :class="
        suggestion.hasField
          ? 'bg-n-alpha-3 text-n-slate-12'
          : 'bg-n-alpha-1 text-n-slate-10'
      "
    >
      <span class="i-lucide-sparkles size-3 flex-shrink-0" />
      <span class="font-medium">{{ suggestion.label }}:</span>
      <span class="truncate max-w-[12rem]">{{ suggestion.value }}</span>

      <button
        v-if="
          suggestion.hasField && !appliedKeys.has(chipKey(suggestion, index))
        "
        type="button"
        class="flex items-center justify-center rounded-full size-4 bg-n-blue-9 text-white hover:bg-n-blue-10 disabled:opacity-50"
        :disabled="pendingKeys.has(chipKey(suggestion, index))"
        :title="t('CONVERSATION.SUGGESTED_ATTRIBUTES.APPLY')"
        @click="applySuggestion(suggestion, index)"
      >
        <span class="i-lucide-plus size-3" />
      </button>
      <span
        v-else-if="appliedKeys.has(chipKey(suggestion, index))"
        class="i-lucide-check size-3 text-n-teal-11"
        :title="t('CONVERSATION.SUGGESTED_ATTRIBUTES.APPLIED')"
      />
      <span v-else class="text-[10px] text-n-slate-9">
        {{ t('CONVERSATION.SUGGESTED_ATTRIBUTES.NO_FIELD') }}
      </span>
    </div>
  </div>
</template>
