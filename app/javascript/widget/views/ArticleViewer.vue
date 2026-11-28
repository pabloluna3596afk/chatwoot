<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { getArticleViewerURL } from 'widget/helpers/urlParamsHelper';
import IframeLoader from 'shared/components/IframeLoader.vue';

const route = useRoute();
const articleURL = computed(() => getArticleViewerURL(route.query.link));
</script>

<template>
  <div class="bg-n-solid-1 h-full">
    <IframeLoader :url="articleURL" />
  </div>
</template>
