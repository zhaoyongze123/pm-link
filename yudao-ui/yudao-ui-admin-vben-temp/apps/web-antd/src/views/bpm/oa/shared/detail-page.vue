<script lang="ts" setup>
import type { BpmOACommonApi, OAModuleApiKey } from '#/api/bpm/oa/common';

import { computed, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';

import { ContentWrap } from '@vben/common-ui';

import { Spin } from 'ant-design-vue';

import { getAttendance } from '#/api/bpm/oa/attendance';
import { getExpense } from '#/api/bpm/oa/expense';
import { getOvertime } from '#/api/bpm/oa/overtime';
import { getSeal } from '#/api/bpm/oa/seal';
import { getTrip } from '#/api/bpm/oa/trip';
import { useDescription } from '#/components/description';

import { getOAModuleViewConfig } from './config';
import { useDetailFormSchema } from './data';

const props = defineProps<{
  id?: string;
  moduleKey: OAModuleApiKey;
}>();

const { query } = useRoute();
const config = getOAModuleViewConfig(props.moduleKey);
const detailRequestMap: Record<
  OAModuleApiKey,
  (id: number) => Promise<BpmOACommonApi.OARecord>
> = {
  attendance: getAttendance,
  expense: getExpense,
  overtime: getOvertime,
  seal: getSeal,
  trip: getTrip,
};

const loading = ref(false);
const formData = ref<BpmOACommonApi.OARecord>();
const queryId = computed(() => query.id as string);

const [Descriptions] = useDescription({
  bordered: true,
  column: 1,
  class: 'mx-4',
  schema: useDetailFormSchema(config),
});

async function getDetailData() {
  try {
    loading.value = true;
    formData.value = await detailRequestMap[props.moduleKey](
      Number(props.id || queryId.value),
    );
  } finally {
    loading.value = false;
  }
}

onMounted(() => {
  getDetailData();
});
</script>

<template>
  <ContentWrap class="m-2">
    <Spin :spinning="loading" tip="加载中...">
      <Descriptions :data="formData" />
    </Spin>
  </ContentWrap>
</template>
