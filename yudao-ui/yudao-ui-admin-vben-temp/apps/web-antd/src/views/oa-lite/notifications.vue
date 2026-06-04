<script lang="ts" setup>
import type { SystemNotifyMessageApi } from '#/api/system/notify/message';

import { computed, onMounted, onUnmounted, reactive, ref } from 'vue';

import { formatDateTime } from '@vben/utils';

import { Button, Empty, message, Modal, Pagination, Spin, Tag } from 'ant-design-vue';

import {
  getMyNotifyMessagePage,
  updateAllNotifyMessageRead,
  updateNotifyMessageRead,
} from '#/api/system/notify/message';
import { router } from '#/router';

type ReadFilter = 'all' | 'read' | 'unread';
const OA_LITE_BODY_THEME_CLASS = 'oa-lite-light-theme';

const loading = ref(false);
const selectedMessage = ref<null | SystemNotifyMessageApi.NotifyMessage>(null);
const readFilter = ref<ReadFilter>('all');
const messages = ref<SystemNotifyMessageApi.NotifyMessage[]>([]);

const pageState = reactive({
  pageNo: 1,
  pageSize: 10,
  total: 0,
});

const readFilterOptions: Array<{ key: ReadFilter; label: string }> = [
  { key: 'all', label: '全部消息' },
  { key: 'unread', label: '未读' },
  { key: 'read', label: '已读' },
];

const unreadCount = computed(
  () => messages.value.filter((item) => !item.readStatus).length,
);

function resolveReadStatus(filter: ReadFilter) {
  if (filter === 'all') {
    return undefined;
  }
  return filter === 'read';
}

async function loadMessages() {
  loading.value = true;
  try {
    const pageResult = await getMyNotifyMessagePage({
      pageNo: pageState.pageNo,
      pageSize: pageState.pageSize,
      readStatus: resolveReadStatus(readFilter.value),
    });
    messages.value = pageResult.list;
    pageState.total = pageResult.total;
  } finally {
    loading.value = false;
  }
}

async function handleFilterChange(filter: ReadFilter) {
  if (readFilter.value === filter) {
    return;
  }
  readFilter.value = filter;
  pageState.pageNo = 1;
  await loadMessages();
}

async function handlePageChange(pageNo: number, pageSize: number) {
  pageState.pageNo = pageNo;
  pageState.pageSize = pageSize;
  await loadMessages();
}

function handleBack() {
  router.push({ name: 'OALite' });
}

function handleViewDetail(item: SystemNotifyMessageApi.NotifyMessage) {
  selectedMessage.value = item;
}

async function handleMarkRead(item: SystemNotifyMessageApi.NotifyMessage) {
  if (item.readStatus) {
    handleViewDetail(item);
    return;
  }
  const hideLoading = message.loading({
    content: '正在标记已读...',
    duration: 0,
  });
  try {
    await updateNotifyMessageRead([item.id]);
    message.success('标记已读成功');
    await loadMessages();
    selectedMessage.value = {
      ...item,
      readStatus: true,
      readTime: new Date(),
    };
  } finally {
    hideLoading();
  }
}

async function handleMarkAllRead() {
  const hideLoading = message.loading({
    content: '正在标记全部已读...',
    duration: 0,
  });
  try {
    await updateAllNotifyMessageRead();
    message.success('全部标记已读成功');
    await loadMessages();
  } finally {
    hideLoading();
  }
}

onMounted(() => {
  document.body.classList.add(OA_LITE_BODY_THEME_CLASS);
  loadMessages();
});

onUnmounted(() => {
  document.body.classList.remove(OA_LITE_BODY_THEME_CLASS);
});
</script>

<template>
  <div class="oa-notify-page">
    <div class="oa-notify-shell">
      <header class="oa-notify-header">
        <div class="oa-notify-header-main">
          <div class="oa-notify-kicker">通知中心</div>
          <div class="oa-notify-title-row">
            <h1>全部历史消息</h1>
            <span class="oa-notify-title-meta">历史存档</span>
          </div>
          <p>统一查看待办、抄送和后续站内提醒，已读记录会持续保留。</p>
        </div>
        <div class="oa-notify-header-actions">
          <Button @click="handleBack">返回 OA</Button>
          <Button type="primary" @click="handleMarkAllRead">全部标记已读</Button>
        </div>
      </header>

      <section class="oa-notify-toolbar">
        <div class="oa-notify-filters">
          <button
            v-for="option in readFilterOptions"
            :key="option.key"
            class="oa-notify-filter"
            :class="{ active: readFilter === option.key }"
            type="button"
            @click="handleFilterChange(option.key)"
          >
            {{ option.label }}
          </button>
        </div>
        <div class="oa-notify-summary">
          <span>当前页未读 {{ unreadCount }} 条</span>
          <span class="oa-notify-summary-divider"></span>
          <span>共 {{ pageState.total }} 条历史消息</span>
        </div>
      </section>

      <section class="oa-notify-list-card">
        <div class="oa-notify-list-head">
          <span class="sender">发送人</span>
          <span class="content">消息内容</span>
          <span class="time">时间</span>
          <span class="status">状态</span>
          <span class="action">操作</span>
        </div>
        <Spin :spinning="loading">
          <template v-if="messages.length > 0">
            <article
              v-for="item in messages"
              :key="item.id"
              class="oa-notify-item"
              :class="{ unread: !item.readStatus }"
            >
              <div class="oa-notify-item-main" @click="handleViewDetail(item)">
                <div class="oa-notify-item-sender">
                  <span v-if="!item.readStatus" class="oa-notify-dot"></span>
                  <span>{{ item.templateNickname }}</span>
                </div>
                <div class="oa-notify-item-content">
                  <div class="oa-notify-item-subject">{{ item.templateContent }}</div>
                </div>
                <div class="oa-notify-item-time">
                  <span>{{ formatDateTime(item.createTime) }}</span>
                  <span v-if="item.readTime" class="oa-notify-read-time">
                    读于 {{ formatDateTime(item.readTime) }}
                  </span>
                </div>
                <div class="oa-notify-item-status">
                  <Tag
                    :color="item.readStatus ? 'default' : 'processing'"
                    class="oa-notify-status-tag"
                    :class="{ read: item.readStatus, unread: !item.readStatus }"
                  >
                    {{ item.readStatus ? '已读' : '未读' }}
                  </Tag>
                </div>
              </div>
              <div class="oa-notify-item-actions">
                <Button type="link" @click="handleViewDetail(item)">查看详情</Button>
                <Button
                  v-if="!item.readStatus"
                  type="link"
                  @click="handleMarkRead(item)"
                >
                  标记已读
                </Button>
              </div>
            </article>
          </template>
          <Empty v-else description="暂无历史消息" />
        </Spin>
      </section>

      <div class="oa-notify-pagination">
        <Pagination
          :current="pageState.pageNo"
          :page-size="pageState.pageSize"
          :total="pageState.total"
          :show-size-changer="true"
          :show-total="(total) => `共 ${total} 条`"
          @change="handlePageChange"
        />
      </div>
    </div>

    <Modal
      :open="selectedMessage !== null"
      title="通知详情"
      :footer="null"
      wrap-class-name="oa-notify-light-modal"
      @cancel="selectedMessage = null"
    >
      <template v-if="selectedMessage">
        <div class="oa-notify-detail">
          <div class="oa-notify-detail-row">
            <span class="label">发送人</span>
            <span>{{ selectedMessage.templateNickname }}</span>
          </div>
          <div class="oa-notify-detail-row">
            <span class="label">状态</span>
            <Tag
              :color="selectedMessage.readStatus ? 'default' : 'processing'"
              class="oa-notify-status-tag"
              :class="{
                read: selectedMessage.readStatus,
                unread: !selectedMessage.readStatus,
              }"
            >
              {{ selectedMessage.readStatus ? '已读' : '未读' }}
            </Tag>
          </div>
          <div class="oa-notify-detail-row">
            <span class="label">发送时间</span>
            <span>{{ formatDateTime(selectedMessage.createTime) }}</span>
          </div>
          <div class="oa-notify-detail-row" v-if="selectedMessage.readTime">
            <span class="label">阅读时间</span>
            <span>{{ formatDateTime(selectedMessage.readTime) }}</span>
          </div>
          <div class="oa-notify-detail-content">
            {{ selectedMessage.templateContent }}
          </div>
        </div>
      </template>
    </Modal>
  </div>
</template>

<style scoped>
.oa-notify-page {
  min-height: 100vh;
  padding: 24px 24px 40px;
  background:
    linear-gradient(180deg, #f7f9fc 0%, #eef3f9 100%);
}

.oa-notify-shell {
  margin: 0 auto;
  max-width: 1180px;
}

.oa-notify-header {
  display: flex;
  gap: 20px;
  align-items: center;
  justify-content: space-between;
  padding: 0 0 18px;
  border-bottom: 1px solid rgba(203, 213, 225, 0.9);
}

.oa-notify-header-main {
  min-width: 0;
}

.oa-notify-kicker {
  margin-bottom: 10px;
  color: #f97316;
  font-size: 12px;
  font-weight: 600;
  letter-spacing: 0.12em;
  text-transform: uppercase;
}

.oa-notify-title-row {
  display: flex;
  gap: 12px;
  align-items: baseline;
}

.oa-notify-header h1 {
  margin: 0;
  color: #0f172a;
  font-size: 24px;
  font-weight: 700;
  letter-spacing: -0.02em;
}

.oa-notify-title-meta {
  color: #94a3b8;
  font-size: 13px;
}

.oa-notify-header p {
  margin: 10px 0 0;
  color: #64748b;
  font-size: 14px;
}

.oa-notify-header-actions {
  display: flex;
  gap: 10px;
  align-items: center;
}

.oa-notify-toolbar,
.oa-notify-list-card {
  margin-top: 18px;
  border: 1px solid rgba(203, 213, 225, 0.8);
  background: rgba(255, 255, 255, 0.94);
}

.oa-notify-toolbar {
  display: flex;
  gap: 16px;
  align-items: center;
  justify-content: space-between;
  padding: 14px 18px;
  border-radius: 14px;
  box-shadow: 0 10px 30px rgba(15, 23, 42, 0.04);
}

.oa-notify-filters {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}

.oa-notify-filter {
  padding: 8px 14px;
  border: 1px solid #d8e1ed;
  border-radius: 10px;
  color: #475569;
  background: #fff;
  cursor: pointer;
  transition: all 0.2s ease;
}

.oa-notify-filter.active {
  border-color: #2563eb;
  color: #1d4ed8;
  background: #eff6ff;
}

.oa-notify-summary {
  display: flex;
  gap: 10px;
  align-items: center;
  color: #64748b;
  font-size: 14px;
}

.oa-notify-summary-divider {
  width: 1px;
  height: 12px;
  background: #cbd5e1;
}

.oa-notify-list-card {
  overflow: hidden;
  border-radius: 16px;
  box-shadow: 0 14px 32px rgba(15, 23, 42, 0.05);
}

.oa-notify-list-head {
  display: grid;
  grid-template-columns: 180px minmax(0, 1.8fr) 220px 90px 120px;
  gap: 16px;
  align-items: center;
  padding: 12px 18px;
  border-bottom: 1px solid #e2e8f0;
  color: #64748b;
  font-size: 12px;
  font-weight: 600;
  letter-spacing: 0.04em;
  background: #f8fafc;
  text-transform: uppercase;
}

.oa-notify-item {
  display: block;
  padding: 0 18px;
  border-bottom: 1px solid rgba(226, 232, 240, 0.9);
  transition: background-color 0.2s ease;
}

.oa-notify-item:hover {
  background: rgba(248, 250, 252, 0.9);
}

.oa-notify-item:last-child {
  border-bottom: none;
}

.oa-notify-item-main {
  display: grid;
  grid-template-columns: 180px minmax(0, 1.8fr) 220px 90px;
  gap: 16px;
  align-items: center;
  min-width: 0;
  padding: 16px 0;
  cursor: pointer;
}

.oa-notify-item.unread .oa-notify-item-content {
  color: #0f172a;
}

.oa-notify-item-sender {
  display: flex;
  gap: 10px;
  align-items: center;
  color: #0f172a;
  font-size: 15px;
  font-weight: 600;
}

.oa-notify-dot {
  width: 8px;
  height: 8px;
  flex: none;
  border-radius: 50%;
  background: #2563eb;
  box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.1);
}

.oa-notify-item-content {
  min-width: 0;
  color: #475569;
  font-size: 14px;
  line-height: 1.6;
}

.oa-notify-item-subject {
  display: -webkit-box;
  overflow: hidden;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
}

.oa-notify-item-time {
  display: flex;
  flex-direction: column;
  gap: 4px;
  justify-content: center;
  color: #475569;
  font-size: 13px;
}

.oa-notify-read-time {
  color: #94a3b8;
  font-size: 12px;
}

.oa-notify-item-status {
  display: flex;
  justify-content: flex-start;
}

.oa-notify-item-actions {
  position: absolute;
  top: 50%;
  right: 18px;
  display: flex;
  gap: 4px;
  align-items: center;
  transform: translateY(-50%);
}

.oa-notify-item {
  position: relative;
  padding-right: 150px;
}

.oa-notify-pagination {
  display: flex;
  justify-content: flex-end;
  margin-top: 18px;
}

.oa-notify-detail {
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.oa-notify-detail-row {
  display: flex;
  gap: 12px;
  align-items: center;
  color: #334155;
}

.oa-notify-detail-row .label {
  min-width: 72px;
  color: #64748b;
}

.oa-notify-detail-content {
  padding: 16px;
  border-radius: 16px;
  color: #0f172a;
  line-height: 1.8;
  background: #f8fafc;
}

:deep(.oa-notify-status-tag.read) {
  border-color: #dbe3f1 !important;
  color: #000 !important;
  background: rgba(248, 250, 252, 0.92) !important;
}

:deep(.oa-notify-status-tag.unread) {
  color: #1d4ed8 !important;
}

@media (max-width: 768px) {
  .oa-notify-page {
    padding: 20px 16px 32px;
  }

  .oa-notify-header,
  .oa-notify-toolbar {
    flex-direction: column;
    align-items: flex-start;
  }

  .oa-notify-header-actions {
    width: 100%;
    justify-content: flex-start;
  }

  .oa-notify-list-head {
    display: none;
  }

  .oa-notify-item {
    padding: 0 16px 16px;
  }

  .oa-notify-item-main {
    grid-template-columns: 1fr;
    gap: 10px;
    padding: 16px 0 10px;
  }

  .oa-notify-item-status {
    justify-content: flex-start;
  }

  .oa-notify-item-actions {
    position: static;
    justify-content: flex-start;
    transform: none;
  }

  .oa-notify-summary {
    flex-wrap: wrap;
  }

  .oa-notify-pagination {
    justify-content: center;
  }
}
</style>

<style lang="scss">
body.oa-lite-light-theme {
  --background: 0 0% 100%;
  --background-deep: 216 20.11% 95.47%;
  --foreground: 210 6% 21%;
  --muted: 240 4.8% 95.9%;
  --muted-foreground: 240 3.8% 46.1%;
  --accent: 240 5% 96%;
  --accent-hover: 200deg 10% 90%;
  --accent-foreground: 240 6% 10%;
  --border: 240 5.9% 90%;
}

body.oa-lite-light-theme .oa-notify-light-modal .ant-modal-content,
body.oa-lite-light-theme .oa-notify-light-modal .ant-modal-header {
  background: #fff !important;
  color: #0f172a !important;
}

body.oa-lite-light-theme .oa-notify-light-modal .ant-modal-content {
  border: 1px solid rgba(148, 163, 184, 0.18);
  border-radius: 28px;
  box-shadow: 0 24px 60px rgba(15, 23, 42, 0.18) !important;
}

body.oa-lite-light-theme .oa-notify-light-modal .ant-modal-header {
  border-bottom: 1px solid #e2e8f0;
  border-radius: 28px 28px 0 0;
}

body.oa-lite-light-theme .oa-notify-light-modal .ant-modal-title,
body.oa-lite-light-theme .oa-notify-light-modal .ant-modal-close,
body.oa-lite-light-theme .oa-notify-light-modal .ant-modal-close-x,
body.oa-lite-light-theme .oa-notify-light-modal .ant-modal-body,
body.oa-lite-light-theme .oa-notify-light-modal .ant-modal-body span,
body.oa-lite-light-theme .oa-notify-light-modal .ant-tag {
  color: #0f172a !important;
}

body.oa-lite-light-theme .oa-notify-light-modal .ant-modal-close:hover {
  background: #f8fafc !important;
}

body.oa-lite-light-theme .oa-notify-light-modal .oa-notify-detail-row .label {
  color: #64748b !important;
}

body.oa-lite-light-theme .oa-notify-light-modal .oa-notify-detail-content {
  background: #f8fafc !important;
  color: #0f172a !important;
}

body.oa-lite-light-theme .oa-notify-page .ant-btn {
  border-radius: 16px;
  box-shadow: none !important;
  transition:
    border-color 0.2s ease,
    background-color 0.2s ease,
    color 0.2s ease;
}

body.oa-lite-light-theme .oa-notify-page .ant-btn-default {
  border-color: #d7e2f0 !important;
  color: #0f172a !important;
  background: #fff !important;
}

body.oa-lite-light-theme .oa-notify-page .ant-btn-default:hover,
body.oa-lite-light-theme .oa-notify-page .ant-btn-default:focus {
  border-color: #93c5fd !important;
  color: #1d4ed8 !important;
  background: #f8fbff !important;
}

body.oa-lite-light-theme .oa-notify-page .ant-btn-primary {
  border-color: #2563eb !important;
  color: #fff !important;
  background: linear-gradient(135deg, #2563eb 0%, #3b82f6 100%) !important;
}

body.oa-lite-light-theme .oa-notify-page .ant-btn-primary:hover,
body.oa-lite-light-theme .oa-notify-page .ant-btn-primary:focus {
  border-color: #1d4ed8 !important;
  background: linear-gradient(135deg, #1d4ed8 0%, #2563eb 100%) !important;
}

body.oa-lite-light-theme .oa-notify-page .ant-btn-link {
  color: #2563eb !important;
  background: transparent !important;
}

body.oa-lite-light-theme .oa-notify-page .ant-btn-link:hover,
body.oa-lite-light-theme .oa-notify-page .ant-btn-link:focus {
  color: #1d4ed8 !important;
  background: rgba(37, 99, 235, 0.06) !important;
}

body.oa-lite-light-theme .oa-notify-page .ant-pagination {
  color: #475569 !important;
}

body.oa-lite-light-theme .oa-notify-page .ant-pagination .ant-pagination-total-text,
body.oa-lite-light-theme .oa-notify-page .ant-pagination .ant-select-selection-item,
body.oa-lite-light-theme .oa-notify-page .ant-pagination .ant-select-arrow,
body.oa-lite-light-theme .oa-notify-page .ant-pagination .ant-pagination-options {
  color: #475569 !important;
}

body.oa-lite-light-theme .oa-notify-page .ant-pagination .ant-pagination-item,
body.oa-lite-light-theme .oa-notify-page .ant-pagination .ant-pagination-prev .ant-pagination-item-link,
body.oa-lite-light-theme .oa-notify-page .ant-pagination .ant-pagination-next .ant-pagination-item-link,
body.oa-lite-light-theme .oa-notify-page .ant-pagination .ant-select-selector {
  border-color: #d7e2f0 !important;
  color: #0f172a !important;
  background: #fff !important;
  box-shadow: none !important;
}

body.oa-lite-light-theme .oa-notify-page .ant-pagination .ant-pagination-item a,
body.oa-lite-light-theme .oa-notify-page .ant-pagination .ant-pagination-prev button,
body.oa-lite-light-theme .oa-notify-page .ant-pagination .ant-pagination-next button {
  color: #0f172a !important;
}

body.oa-lite-light-theme .oa-notify-page .ant-pagination .ant-pagination-item:hover,
body.oa-lite-light-theme .oa-notify-page .ant-pagination .ant-pagination-prev:hover .ant-pagination-item-link,
body.oa-lite-light-theme .oa-notify-page .ant-pagination .ant-pagination-next:hover .ant-pagination-item-link,
body.oa-lite-light-theme .oa-notify-page .ant-pagination .ant-select-selector:hover {
  border-color: #93c5fd !important;
  color: #1d4ed8 !important;
}

body.oa-lite-light-theme .oa-notify-page .ant-pagination .ant-pagination-item-active {
  border-color: #2563eb !important;
  background: #eff6ff !important;
}

body.oa-lite-light-theme .oa-notify-page .ant-pagination .ant-pagination-item-active a {
  color: #2563eb !important;
}

body.oa-lite-light-theme .ant-select-dropdown {
  border: 1px solid rgba(148, 163, 184, 0.18) !important;
  border-radius: 16px !important;
  background: #fff !important;
  box-shadow: 0 18px 40px rgba(15, 23, 42, 0.12) !important;
}

body.oa-lite-light-theme .ant-select-dropdown .ant-select-item {
  color: #0f172a !important;
}

body.oa-lite-light-theme .ant-select-dropdown .ant-select-item-option-active:not(.ant-select-item-option-disabled),
body.oa-lite-light-theme .ant-select-dropdown .ant-select-item-option-selected:not(.ant-select-item-option-disabled) {
  background: #eff6ff !important;
  color: #1d4ed8 !important;
}
</style>
