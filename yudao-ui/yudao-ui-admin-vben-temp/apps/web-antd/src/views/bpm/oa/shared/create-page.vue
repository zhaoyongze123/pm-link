<script lang="ts" setup>
import type { BpmOACommonApi, OAModuleApiKey } from '#/api/bpm/oa/common';
import type { BpmProcessInstanceApi } from '#/api/bpm/processInstance';

import { computed, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';

import { confirm, Page, useVbenForm } from '@vben/common-ui';
import { BpmCandidateStrategyEnum, BpmNodeIdEnum } from '@vben/constants';
import { useTabs } from '@vben/hooks';
import { IconifyIcon } from '@vben/icons';

import { Button, Card, Col, message, Row, Space } from 'ant-design-vue';
import dayjs from 'dayjs';

import { createAttendance, getAttendance } from '#/api/bpm/oa/attendance';
import { getProcessDefinition } from '#/api/bpm/definition';
import { createExpense, getExpense } from '#/api/bpm/oa/expense';
import { createOvertime, getOvertime } from '#/api/bpm/oa/overtime';
import { createSeal, getSeal } from '#/api/bpm/oa/seal';
import { createTrip, getTrip } from '#/api/bpm/oa/trip';
import { getApprovalDetail as getApprovalDetailApi } from '#/api/bpm/processInstance';
import { $t } from '#/locales';
import { router } from '#/router';
import ProcessInstanceTimeline from '#/views/bpm/processInstance/detail/modules/time-line.vue';

import { getOAModuleViewConfig } from './config';
import { useFormSchema } from './data';

const props = defineProps<{
  moduleKey: OAModuleApiKey;
}>();

const { closeCurrentTab } = useTabs();
const { query } = useRoute();
const config = getOAModuleViewConfig(props.moduleKey);
const createRequestMap: Record<
  OAModuleApiKey,
  (data: BpmOACommonApi.OARecord) => Promise<unknown>
> = {
  attendance: createAttendance,
  expense: createExpense,
  overtime: createOvertime,
  seal: createSeal,
  trip: createTrip,
};
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

const formLoading = ref(false);
const processTimeLineLoading = ref(false);
const startUserSelectTasks = ref<BpmProcessInstanceApi.ApprovalNodeInfo[]>([]);
const startUserSelectAssignees = ref<Record<string, number[]>>({});
const activityNodes = ref<BpmProcessInstanceApi.ApprovalNodeInfo[]>([]);
const processDefinitionId = ref('');
const formData = ref<Partial<BpmOACommonApi.OARecord>>({});

const getTitle = computed(() => {
  return formData.value?.id
    ? `重新发起${config.title}`
    : $t('ui.actionTitle.create', [config.title]);
});

const [Form, formApi] = useVbenForm({
  commonConfig: {
    componentProps: {
      class: 'w-full',
    },
    formItemClass: 'col-span-2',
    labelWidth: 100,
  },
  layout: 'horizontal',
  schema: useFormSchema(config),
  showDefaultActions: false,
});

async function getApprovalDetail() {
  processTimeLineLoading.value = true;
  try {
    const data = await getApprovalDetailApi({
      processDefinitionId: processDefinitionId.value,
      activityId: BpmNodeIdEnum.START_USER_NODE_ID,
      processVariablesStr: JSON.stringify({
        day: Math.max(
          dayjs(formData.value?.endTime).diff(dayjs(formData.value?.startTime), 'day'),
          0,
        ),
      }),
    });
    if (!data) {
      message.error('查询不到审批详情信息');
      return;
    }
    activityNodes.value = data.activityNodes;
    startUserSelectTasks.value = data.activityNodes?.filter(
      (node) =>
        BpmCandidateStrategyEnum.START_USER_SELECT === node.candidateStrategy,
    );
    startUserSelectAssignees.value = {};
    for (const node of startUserSelectTasks.value) {
      startUserSelectAssignees.value[node.id] = [];
    }
  } finally {
    processTimeLineLoading.value = false;
  }
}

function selectUserConfirm(id: string, userList: any[]) {
  startUserSelectAssignees.value[id] = userList?.map((item: any) => item.id);
}

async function loadDetail(id: number) {
  try {
    formLoading.value = true;
    const data = await detailRequestMap[props.moduleKey](id);
    if (!data) {
      message.error(`重新发起${config.title}失败，原因：原申请不存在`);
      return;
    }
    formData.value = {
      ...formData.value,
      id: data.id,
      type: data.type,
      reason: data.reason,
      startTime: data.startTime,
      endTime: data.endTime,
    };
    await formApi.setValues({
      type: data.type,
      reason: data.reason,
      startTime: data.startTime,
      endTime: data.endTime,
    });
  } finally {
    formLoading.value = false;
  }
}

async function onSubmit() {
  const { valid } = await formApi.validate();
  if (!valid) {
    return;
  }
  for (const userTask of startUserSelectTasks.value) {
    if (
      Array.isArray(startUserSelectAssignees.value[userTask.id]) &&
      startUserSelectAssignees.value[userTask.id].length === 0
    ) {
      return message.warning(`请选择${userTask.name}的审批人`);
    }
  }

  const values = (await formApi.getValues()) as BpmOACommonApi.OARecord;
  const submitData: BpmOACommonApi.OARecord = {
    ...values,
    endTime: Number(values.endTime),
    reason: values.reason.trim(),
    startTime: Number(values.startTime),
  };
  if (startUserSelectTasks.value.length > 0) {
    submitData.startUserSelectAssignees = startUserSelectAssignees.value;
  }

  try {
    formLoading.value = true;
    await createRequestMap[props.moduleKey](submitData);
    message.success($t('ui.actionMessage.operationSuccess'));
    await closeCurrentTab();
    await router.push({
      name: config.routeNames.index,
    });
  } finally {
    formLoading.value = false;
  }
}

function onBack() {
  confirm({
    content: '确定要返回上一页吗？请先保存您填写的信息！',
    icon: 'warning',
    beforeClose({ isConfirm }) {
      if (isConfirm) {
        closeCurrentTab();
      }
      return Promise.resolve(true);
    },
  });
}

onMounted(async () => {
  const processDefinitionDetail: any = await getProcessDefinition(
    undefined,
    config.processDefinitionKey,
  );
  if (!processDefinitionDetail) {
    message.error(`OA ${config.title}的流程模型未配置，请检查`);
    return;
  }
  processDefinitionId.value = processDefinitionDetail.id;

  if (query.id) {
    await loadDetail(Number(query.id));
  }

  await getApprovalDetail();
});
</script>

<template>
  <Page>
    <Row :gutter="16">
      <Col :span="16">
        <Card :title="getTitle" class="w-full" v-loading="formLoading">
          <template #extra>
            <Button type="default" @click="onBack">
              <IconifyIcon icon="lucide:arrow-left" />
              返回
            </Button>
          </template>

          <Form />
          <template #actions>
            <Space warp :size="12" class="w-full px-6">
              <Button type="primary" @click="onSubmit" :loading="formLoading">
                提交
              </Button>
            </Space>
          </template>
        </Card>
      </Col>
      <Col :span="8">
        <Card title="流程" class="w-full" v-loading="processTimeLineLoading">
          <ProcessInstanceTimeline
            :activity-nodes="activityNodes"
            :show-status-icon="false"
            @select-user-confirm="selectUserConfirm"
          />
        </Card>
      </Col>
    </Row>
  </Page>
</template>
