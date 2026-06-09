<!-- 审批详情的右侧：审批流 -->
<script lang="ts" setup>
import type { BpmProcessInstanceApi } from '#/api/bpm/processInstance';

import { ref } from 'vue';
import { useRouter } from 'vue-router';

import { useVbenModal } from '@vben/common-ui';
import {
  BpmCandidateStrategyEnum,
  BpmNodeTypeEnum,
  BpmTaskStatusEnum,
} from '@vben/constants';
import { IconifyIcon } from '@vben/icons';
import { formatDateTime, isEmpty } from '@vben/utils';

import { Avatar, Button, Image, Timeline, Tooltip } from 'ant-design-vue';

import { UserSelectModal } from '#/views/system/user/components';

defineOptions({ name: 'BpmProcessInstanceTimeline' });

const props = withDefaults(
  defineProps<{
    activityNodes: BpmProcessInstanceApi.ApprovalNodeInfo[]; // 审批节点信息
    enableApproveUserSelect?: boolean; // 是否开启审批人自选功能
    showStatusIcon?: boolean; // 是否显示头像右下角状态图标
  }>(),
  {
    showStatusIcon: true, // 默认值为 true
    enableApproveUserSelect: false, // 默认值为 false
  },
);

const emit = defineEmits<{
  selectUserConfirm: [activityId: string, userList: any[]];
}>();

const { push } = useRouter();

const statusIconMap: Record<
  string,
  { animation?: string; color: string; icon: string }
> = {
  '-2': { color: '#909398', icon: 'lucide:skip-forward' }, // 跳过
  '-1': { color: '#909398', icon: 'lucide:clock-3' }, // 审批未开始
  '0': { color: '#ff943e', icon: 'lucide:loader-circle', animation: 'animate-spin' }, // 待审批
  '1': { color: '#448ef7', icon: 'lucide:loader-circle', animation: 'animate-spin' }, // 审批中
  '2': { color: '#00b32a', icon: 'lucide:check' }, // 审批通过
  '3': { color: '#f46b6c', icon: 'lucide:x' }, // 审批不通过
  '4': { color: '#cccccc', icon: 'lucide:ban' }, // 已取消
  '5': { color: '#f46b6c', icon: 'lucide:corner-up-left' }, // 退回
  '6': { color: '#448ef7', icon: 'lucide:clock-3' }, // 委派中
  '7': { color: '#00b32a', icon: 'lucide:badge-check' }, // 审批通过中
}; // 状态图标映射
const nodeTypeSvgMap = {
  // 结束节点
  [BpmNodeTypeEnum.END_EVENT_NODE]: {
    color: '#909398',
    icon: 'lucide:flag',
  },
  // 开始节点
  [BpmNodeTypeEnum.START_USER_NODE]: {
    color: '#909398',
    icon: 'lucide:user-round',
  },
  // 用户任务节点
  [BpmNodeTypeEnum.USER_TASK_NODE]: {
    color: '#ff943e',
    icon: 'lucide:badge-check',
  },
  // 事务节点
  [BpmNodeTypeEnum.TRANSACTOR_NODE]: {
    color: '#ff943e',
    icon: 'lucide:file-pen-line',
  },
  // 复制任务节点
  [BpmNodeTypeEnum.COPY_TASK_NODE]: {
    color: '#3296fb',
    icon: 'lucide:copy',
  },
  // 条件分支节点
  [BpmNodeTypeEnum.CONDITION_NODE]: {
    color: '#14bb83',
    icon: 'lucide:git-branch-plus',
  },
  // 并行分支节点
  [BpmNodeTypeEnum.PARALLEL_BRANCH_NODE]: {
    color: '#14bb83',
    icon: 'lucide:split',
  },
  // 子流程节点
  [BpmNodeTypeEnum.CHILD_PROCESS_NODE]: {
    color: '#14bb83',
    icon: 'lucide:workflow',
  },
} as Record<BpmNodeTypeEnum, { color: string; icon: string }>; // 节点类型图标映射
const onlyStatusIconShow = [-1, 0, 1]; // 只有状态是 -1、0、1 才展示头像右小角状态小 icon

/** 获取审批节点类型图标 */
function getApprovalNodeTypeIcon(nodeType: BpmNodeTypeEnum) {
  return nodeTypeSvgMap[nodeType]?.icon;
}

/** 获取审批节点图标 */
function getApprovalNodeIcon(taskStatus: number, nodeType: BpmNodeTypeEnum) {
  if (taskStatus === BpmTaskStatusEnum.NOT_START) {
    return statusIconMap[taskStatus]?.icon || 'mdi:clock-outline';
  }
  if (
    [
      BpmNodeTypeEnum.CHILD_PROCESS_NODE,
      BpmNodeTypeEnum.END_EVENT_NODE,
      BpmNodeTypeEnum.START_USER_NODE,
      BpmNodeTypeEnum.TRANSACTOR_NODE,
      BpmNodeTypeEnum.USER_TASK_NODE,
    ].includes(nodeType)
  ) {
    return statusIconMap[taskStatus]?.icon || 'mdi:clock-outline';
  }
  return 'mdi:clock-outline';
}

/** 获取审批节点颜色 */
function getApprovalNodeColor(taskStatus: number) {
  return statusIconMap[taskStatus]?.color;
}

/** 获取审批节点时间 */
function getApprovalNodeTime(node: BpmProcessInstanceApi.ApprovalNodeInfo) {
  if (node.nodeType === BpmNodeTypeEnum.START_USER_NODE && node.startTime) {
    return formatDateTime(node.startTime);
  }
  if (node.endTime) {
    return formatDateTime(node.endTime);
  }
  if (node.startTime) {
    return formatDateTime(node.startTime);
  }
  return '';
}

const [UserSelectModalComp, userSelectModalApi] = useVbenModal({
  connectedComponent: UserSelectModal,
  destroyOnClose: true,
});
const selectedActivityNodeId = ref<string>();
const customApproveUsers = ref<Record<string, any[]>>({}); // key：activityId，value：用户列表

/** 打开选择用户弹窗 */
const handleSelectUser = (activityId: string, selectedList: any[]) => {
  selectedActivityNodeId.value = activityId;
  userSelectModalApi
    .setData({ userIds: selectedList.map((item) => item.id) })
    .open();
};

/** 选择用户完成 */
const selectedUsers = ref<number[]>([]);
function handleUserSelectConfirm(userList: any[]) {
  if (!selectedActivityNodeId.value) {
    return;
  }
  customApproveUsers.value[selectedActivityNodeId.value] = userList || [];

  emit('selectUserConfirm', selectedActivityNodeId.value, userList);
}

/** 跳转子流程 */
function handleChildProcess(activity: any) {
  if (!activity.processInstanceId) {
    return;
  }
  push({
    name: 'BpmProcessInstanceDetail',
    query: {
      id: activity.processInstanceId,
    },
  });
}

/** 判断是否需要显示自定义选择审批人 */
function shouldShowCustomUserSelect(
  activity: BpmProcessInstanceApi.ApprovalNodeInfo,
) {
  return (
    isEmpty(activity.tasks) &&
    ((BpmCandidateStrategyEnum.START_USER_SELECT ===
      activity.candidateStrategy &&
      isEmpty(activity.candidateUsers)) ||
      (props.enableApproveUserSelect &&
        BpmCandidateStrategyEnum.APPROVE_USER_SELECT ===
          activity.candidateStrategy))
  );
}

/** 判断是否需要显示审批意见 */
function shouldShowApprovalReason(task: any, nodeType: BpmNodeTypeEnum) {
  return (
    task.reason &&
    [BpmNodeTypeEnum.END_EVENT_NODE, BpmNodeTypeEnum.USER_TASK_NODE].includes(
      nodeType,
    )
  );
}

/** 用户选择弹窗关闭 */
function handleUserSelectClosed() {
  selectedUsers.value = [];
}

/** 用户选择弹窗取消 */
function handleUserSelectCancel() {
  selectedUsers.value = [];
}

/** 设置自定义审批人 */
const setCustomApproveUsers = (activityId: string, users: any[]) => {
  customApproveUsers.value[activityId] = users || [];
};

/** 批量设置多个节点的自定义审批人 */
const batchSetCustomApproveUsers = (data: Record<string, any[]>) => {
  Object.keys(data).forEach((activityId) => {
    customApproveUsers.value[activityId] = data[activityId] || [];
  });
};

defineExpose({ setCustomApproveUsers, batchSetCustomApproveUsers });
</script>

<template>
  <div class="oa-process-timeline">
    <Timeline class="oa-process-timeline-list">
      <!-- 遍历每个审批节点 -->
      <Timeline.Item
        v-for="(activity, index) in activityNodes"
        :key="index"
        :color="getApprovalNodeColor(activity.status)"
      >
        <template #dot>
          <div class="oa-process-timeline-dot-wrap">
            <div
              class="oa-process-timeline-dot"
              :style="{
                backgroundColor: getApprovalNodeColor(activity.status) || 'var(--oa-accent)',
              }"
            >
              <IconifyIcon
                :icon="getApprovalNodeTypeIcon(activity.nodeType)"
                class="oa-process-timeline-dot-icon"
              />
            </div>
            <div
              v-if="showStatusIcon"
              class="oa-process-timeline-status"
              :style="{
                backgroundColor: getApprovalNodeColor(activity.status),
              }"
            >
              <IconifyIcon
                :icon="getApprovalNodeIcon(activity.status, activity.nodeType)"
                class="oa-process-timeline-status-icon"
                :class="[statusIconMap[activity.status]?.animation]"
              />
            </div>
          </div>
        </template>

        <div
          class="oa-process-timeline-card"
          :id="`activity-task-${activity.id}-${index}`"
        >
          <!-- 第一行：节点名称、时间 -->
          <div class="oa-process-timeline-head">
            <div class="oa-process-timeline-title">
              {{ activity.name }}
              <span v-if="activity.status === BpmTaskStatusEnum.SKIP">
                【跳过】
              </span>
            </div>
            <!-- 信息：时间 -->
            <div
              v-if="activity.status !== BpmTaskStatusEnum.NOT_START"
              class="oa-process-timeline-time"
            >
              {{ getApprovalNodeTime(activity) }}
            </div>
          </div>

          <!-- 子流程节点 -->
          <div v-if="activity.nodeType === BpmNodeTypeEnum.CHILD_PROCESS_NODE">
            <Button
              type="primary"
              ghost
              size="small"
              @click="handleChildProcess(activity)"
              :disabled="!activity.processInstanceId"
            >
              查看子流程
            </Button>
          </div>

          <!-- 需要自定义选择审批人 -->
          <div
            v-if="shouldShowCustomUserSelect(activity)"
            class="oa-process-timeline-users"
          >
            <Tooltip title="添加用户" placement="left">
              <Button
                type="primary"
                size="middle"
                ghost
                class="oa-process-timeline-add-user"
                @click="
                  handleSelectUser(
                    activity.id,
                    customApproveUsers[activity.id] ?? [],
                  )
                "
              >
                <template #icon>
                  <IconifyIcon icon="lucide:user-plus" class="size-4" />
                </template>
              </Button>
            </Tooltip>

            <div
              v-for="(user, userIndex) in customApproveUsers[activity.id]"
              :key="user.id || userIndex"
              class="oa-process-timeline-user-chip"
            >
              <Avatar
                class="!m-1"
                :size="28"
                v-if="user.avatar"
                :src="user.avatar"
              />

              <Avatar class="!m-1" :size="28" v-else>
                <span>{{ user.nickname.substring(0, 1) }}</span>
              </Avatar>
              <span class="oa-process-timeline-user-name">{{ user.nickname }}</span>
            </div>
          </div>

          <div v-else class="oa-process-timeline-users">
            <!-- 情况一：遍历每个审批节点下的【进行中】task 任务 -->
            <div
              v-for="(task, idx) in activity.tasks"
              :key="idx"
              class="flex flex-col gap-2 pr-2"
            >
              <div
                class="oa-process-timeline-task-user"
                v-if="task.assigneeUser || task.ownerUser"
              >
                <!-- 信息：头像昵称 -->
                <div class="oa-process-timeline-user-chip">
                  <template
                    v-if="
                      task.assigneeUser?.avatar || task.assigneeUser?.nickname
                    "
                  >
                    <Avatar
                      class="!m-1"
                      :size="28"
                      v-if="task.assigneeUser?.avatar"
                      :src="task.assigneeUser?.avatar"
                    />
                    <Avatar class="!m-1" :size="28" v-else>
                      {{ task.assigneeUser?.nickname.substring(0, 1) }}
                    </Avatar>
                    {{ task.assigneeUser?.nickname }}
                  </template>
                  <template
                    v-else-if="
                      task.ownerUser?.avatar || task.ownerUser?.nickname
                    "
                  >
                    <Avatar
                      class="!m-1"
                      :size="28"
                      v-if="task.ownerUser?.avatar"
                      :src="task.ownerUser?.avatar"
                    />
                    <Avatar class="!m-1" :size="28" v-else>
                      {{ task.ownerUser?.nickname.substring(0, 1) }}
                    </Avatar>
                    {{ task.ownerUser?.nickname }}
                  </template>

                  <!-- 信息：任务状态图标 -->
                  <div
                    v-if="
                      showStatusIcon && onlyStatusIconShow.includes(task.status)
                    "
                    class="oa-process-timeline-mini-status"
                    :style="{
                      backgroundColor: statusIconMap[task.status]?.color,
                    }"
                  >
                    <IconifyIcon
                      :icon="statusIconMap[task.status]?.icon || 'lucide:clock'"
                      class="oa-process-timeline-mini-status-icon"
                      :class="[statusIconMap[task.status]?.animation]"
                    />
                  </div>
                </div>
              </div>

              <!-- 审批意见和签名 -->
              <teleport defer :to="`#activity-task-${activity.id}-${index}`">
                <div
                  v-if="shouldShowApprovalReason(task, activity.nodeType)"
                  class="oa-process-timeline-note"
                >
                  审批意见：{{ task.reason }}
                </div>
                <div
                  v-if="
                    task.signPicUrl &&
                    activity.nodeType === BpmNodeTypeEnum.USER_TASK_NODE
                  "
                  class="oa-process-timeline-note oa-process-timeline-signature"
                >
                  签名：
                  <Image
                    class="ml-2"
                    :width="180"
                    :height="60"
                    :src="task.signPicUrl"
                    :preview="{ src: task.signPicUrl }"
                  />
                </div>
              </teleport>
            </div>

            <!-- 情况二：遍历每个审批节点下的【候选的】task 任务 -->
            <div
              v-for="(user, userIndex) in activity.candidateUsers"
              :key="userIndex"
              class="oa-process-timeline-user-chip"
            >
              <Avatar
                class="!m-1"
                :size="28"
                v-if="user.avatar"
                :src="user.avatar"
              />
              <Avatar class="!m-1" :size="28" v-else>
                {{ user.nickname.substring(0, 1) }}
              </Avatar>
              <span class="oa-process-timeline-user-name">
                {{ user.nickname }}
              </span>

              <!-- 候选任务状态图标 -->
              <div
                v-if="showStatusIcon"
                class="oa-process-timeline-mini-status"
                :style="{ backgroundColor: statusIconMap['-1']?.color }"
              >
                <IconifyIcon
                  class="oa-process-timeline-mini-status-icon"
                  :icon="statusIconMap['-1']?.icon || 'lucide:clock'"
                />
              </div>
            </div>
          </div>
        </div>
      </Timeline.Item>
    </Timeline>

    <!-- 用户选择弹窗 -->
    <UserSelectModalComp
      class="w-3/5"
      v-model:value="selectedUsers"
      :multiple="true"
      title="选择用户"
      @confirm="handleUserSelectConfirm"
      @closed="handleUserSelectClosed"
      @cancel="handleUserSelectCancel"
    />
  </div>
</template>

<style scoped>
.oa-process-timeline {
  padding-top: 6px;
}

.oa-process-timeline-list {
  padding-top: 0;
}

.oa-process-timeline :deep(.ant-timeline-item-tail) {
  inset-inline-start: 17px;
  border-inline-start: 1px solid var(--oa-shell-border);
}

.oa-process-timeline :deep(.ant-timeline-item-head) {
  inset-inline-start: 6px;
}

.oa-process-timeline :deep(.ant-timeline-item-content) {
  margin-inline-start: 48px;
}

.oa-process-timeline-dot-wrap {
  position: relative;
}

.oa-process-timeline-dot {
  display: flex;
  width: 22px;
  height: 22px;
  align-items: center;
  justify-content: center;
  border: 1px solid var(--oa-shell-border);
  border-radius: 6px;
  background: color-mix(
    in srgb,
    var(--oa-shell-surface-muted) 84%,
    var(--oa-shell-surface) 16%
  );
  color: var(--oa-accent);
  box-shadow: inset 0 0 0 1px rgb(255 255 255 / 6%);
}

.oa-process-timeline-dot-icon {
  font-size: 13px;
  color: inherit;
  stroke-width: 2;
}

.oa-process-timeline-status {
  position: absolute;
  right: -2px;
  bottom: -2px;
  display: flex;
  width: 12px;
  height: 12px;
  align-items: center;
  justify-content: center;
  border: 1px solid var(--oa-shell-border);
  border-radius: 999px;
  background: var(--oa-shell-surface);
}

.oa-process-timeline-status-icon,
.oa-process-timeline-mini-status-icon {
  color: var(--oa-accent-contrast);
  font-size: 10px;
}

.oa-process-timeline-card {
  display: flex;
  min-width: 0;
  flex-direction: column;
  gap: 10px;
  padding: 2px 0 18px;
  border-bottom: 1px solid color-mix(in srgb, var(--oa-shell-border) 88%, transparent);
  background: transparent;
}

.oa-process-timeline-head {
  display: flex;
  width: 100%;
  gap: 12px;
  align-items: baseline;
}

.oa-process-timeline-title {
  font-size: 15px;
  font-weight: 600;
  color: var(--oa-ink);
  line-height: 1.4;
}

.oa-process-timeline-time {
  margin-left: auto;
  font-size: 12px;
  color: var(--oa-ink-faint);
  white-space: nowrap;
}

.oa-process-timeline-users {
  display: flex;
  flex-wrap: wrap;
  gap: 10px 16px;
  align-items: center;
}

.oa-process-timeline-add-user {
  border-radius: 0;
}

.oa-process-timeline-user-chip {
  position: relative;
  display: inline-flex;
  min-height: 28px;
  align-items: center;
  gap: 8px;
  padding: 0 10px 0 0;
  border: 0;
  border-radius: 0;
  background: transparent;
  color: var(--oa-ink);
}

.oa-process-timeline-user-name {
  font-size: 13px;
  color: var(--oa-ink);
  font-weight: 500;
}

.oa-process-timeline-task-user {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding-right: 10px;
}

.oa-process-timeline-mini-status {
  position: absolute;
  right: 6px;
  bottom: -1px;
  display: flex;
  width: 12px;
  height: 12px;
  align-items: center;
  justify-content: center;
  border: 1px solid var(--oa-shell-border);
  border-radius: 999px;
  background: var(--oa-shell-surface);
}

.oa-process-timeline-note {
  width: 100%;
  padding: 0 0 0 14px;
  font-size: 12px;
  color: var(--oa-ink-soft);
  line-height: 1.7;
  border-left: 1px solid var(--oa-shell-border);
  background: transparent;
}

.oa-process-timeline-signature {
  align-items: center;
}

@media (max-width: 768px) {
  .oa-process-timeline-card {
    padding: 2px 0 16px;
  }

  .oa-process-timeline-head {
    flex-direction: column;
    align-items: flex-start;
  }

  .oa-process-timeline-time {
    margin-left: 0;
  }
}
</style>
