<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { answerBlocks } from 'shared/helpers/flowAnswers';
import { saveTargets, saveTargetLabel } from './flowSaveTargets';
import FlowPreviewMessage from './FlowPreviewMessage.vue';

const props = defineProps({
  flowName: { type: String, required: true },
  definition: { type: Object, required: true },
  answers: { type: Object, required: true },
  attributes: { type: Array, default: () => [] },
});
defineEmits(['reset', 'edit']);
const { t } = useI18n();
const showTargets = ref(false);
const destinations = computed(() =>
  answerBlocks(props.definition)
    .filter(block => block.save_to && Object.hasOwn(props.answers, block.key))
    .map(block => {
      const target = saveTargets(block, props.attributes).find(
        item => item.key === block.save_to.target
      );
      return {
        key: block.key,
        label: block.label,
        target: target ? saveTargetLabel(target, t) : block.save_to.target,
      };
    })
);
</script>

<template>
  <div
    class="flex flex-col min-w-0 w-full gap-4 p-4"
    data-testid="flow-preview-result"
  >
    <h3 class="text-heading-3" tabindex="-1" data-testid="flow-result-heading">
      {{ $t('WHATSAPP_FLOWS.SIMULATOR.RESULT') }}
    </h3>
    <FlowPreviewMessage
      kind="sent"
      :flow-name="flowName"
      :definition="definition"
      :answers="answers"
    />
    <FlowPreviewMessage
      kind="response"
      :flow-name="flowName"
      :definition="definition"
      :answers="answers"
    />
    <div v-if="destinations.length">
      <Button
        variant="ghost"
        color="slate"
        size="sm"
        :label="$t('WHATSAPP_FLOWS.SIMULATOR.DESTINATIONS')"
        :icon="showTargets ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        :aria-expanded="showTargets"
        aria-controls="flow-preview-destinations"
        data-testid="flow-preview-destinations-toggle"
        @click="showTargets = !showTargets"
      />
      <ul
        v-if="showTargets"
        id="flow-preview-destinations"
        class="grid gap-2 mt-2 text-xs text-n-slate-11 list-none"
      >
        <li v-for="item in destinations" :key="item.key">
          {{
            $t('WHATSAPP_FLOWS.SIMULATOR.DESTINATION', {
              field: item.label,
              target: item.target,
            })
          }}
        </li>
      </ul>
    </div>
    <p class="text-xs text-n-slate-11">
      {{ $t('WHATSAPP_FLOWS.SIMULATOR.LOCAL_ONLY') }}
    </p>
    <div class="flex flex-wrap gap-2">
      <Button
        size="sm"
        :label="$t('WHATSAPP_FLOWS.SIMULATOR.RESET')"
        data-testid="flow-result-reset"
        @click="$emit('reset')"
      />
      <Button
        variant="ghost"
        color="slate"
        size="sm"
        :label="$t('WHATSAPP_FLOWS.SIMULATOR.BACK_TO_EDIT')"
        data-testid="flow-result-edit"
        @click="$emit('edit')"
      />
    </div>
  </div>
</template>
