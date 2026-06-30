import type { VbenFormSchema } from '#/adapter/form';
import type { VxeTableGridOptions } from '#/adapter/vxe-table';
import type { SystemPartyFileApi } from '#/api/system/party-file';

import { CommonStatusEnum, DICT_TYPE } from '@vben/constants';
import { getDictOptions } from '@vben/hooks';
import { handleTree } from '@vben/utils';

import { z } from '#/adapter/form';
import { getSimpleDeptList } from '#/api/system/dept';
import { getSimpleRoleList } from '#/api/system/role';
import {
  getSimplePartyFileCategoryList,
} from '#/api/system/party-file';
import { getSimpleUserList } from '#/api/system/user';

export function useCategoryFormSchema(): VbenFormSchema[] {
  return [
    {
      fieldName: 'id',
      component: 'Input',
      dependencies: { triggerFields: [''], show: () => false },
    },
    {
      fieldName: 'parentId',
      label: '上级分类',
      component: 'ApiTreeSelect',
      componentProps: {
        api: async () => {
          const data = await getSimplePartyFileCategoryList();
          data.unshift({
            id: 0,
            name: '顶级分类',
            parentId: 0,
            sort: 0,
            status: 0,
          });
          return handleTree(data);
        },
        labelField: 'name',
        valueField: 'id',
        childrenField: 'children',
        treeDefaultExpandAll: true,
        placeholder: '请选择上级分类',
      },
      rules: 'selectRequired',
    },
    {
      fieldName: 'name',
      label: '分类名称',
      component: 'Input',
      componentProps: {
        placeholder: '请输入分类名称',
      },
      rules: 'required',
    },
    {
      fieldName: 'sort',
      label: '排序',
      component: 'InputNumber',
      componentProps: {
        min: 0,
        placeholder: '请输入排序',
      },
      rules: 'required',
    },
    {
      fieldName: 'status',
      label: '状态',
      component: 'RadioGroup',
      componentProps: {
        options: getDictOptions(DICT_TYPE.COMMON_STATUS, 'number'),
        buttonStyle: 'solid',
        optionType: 'button',
      },
      rules: z.number().default(CommonStatusEnum.ENABLE),
    },
  ];
}

export function useCategoryColumns(): VxeTableGridOptions['columns'] {
  return [
    { type: 'checkbox', width: 40 },
    {
      field: 'name',
      title: '分类名称',
      minWidth: 180,
      treeNode: true,
    },
    {
      field: 'sort',
      title: '排序',
      minWidth: 100,
    },
    {
      field: 'status',
      title: '状态',
      minWidth: 100,
      cellRender: {
        name: 'CellDict',
        props: { type: DICT_TYPE.COMMON_STATUS },
      },
    },
    {
      field: 'createTime',
      title: '创建时间',
      minWidth: 180,
      formatter: 'formatDateTime',
    },
    {
      title: '操作',
      width: 220,
      fixed: 'right',
      slots: { default: 'actions' },
    },
  ];
}

export function usePartyFileFormSchema(): VbenFormSchema[] {
  return [
    {
      fieldName: 'id',
      component: 'Input',
      dependencies: { triggerFields: [''], show: () => false },
    },
    {
      fieldName: 'title',
      label: '文件标题',
      component: 'Input',
      componentProps: {
        placeholder: '请输入文件标题',
      },
      rules: 'required',
    },
    {
      fieldName: 'categoryId',
      label: '所属分类',
      component: 'ApiTreeSelect',
      componentProps: {
        api: async () => handleTree(await getSimplePartyFileCategoryList()),
        labelField: 'name',
        valueField: 'id',
        childrenField: 'children',
        treeDefaultExpandAll: true,
        placeholder: '请选择所属分类',
      },
      rules: 'selectRequired',
    },
    {
      fieldName: 'summary',
      label: '摘要',
      component: 'Textarea',
      componentProps: {
        maxlength: 255,
        placeholder: '请输入摘要',
      },
    },
    {
      fieldName: 'content',
      label: '正文',
      component: 'RichTextarea',
    },
    {
      fieldName: 'attachmentFileIds',
      label: '附件',
      component: 'FileUpload',
      componentProps: {
        maxNumber: 10,
        multiple: true,
        showDescription: true,
        accept: [],
      },
    },
    {
      fieldName: 'publishTime',
      label: '发布时间',
      component: 'DatePicker',
      componentProps: {
        showTime: true,
        valueFormat: 'YYYY-MM-DD HH:mm:ss',
        placeholder: '请选择发布时间',
      },
      rules: 'required',
    },
    {
      fieldName: 'status',
      label: '状态',
      component: 'RadioGroup',
      componentProps: {
        options: getDictOptions(DICT_TYPE.COMMON_STATUS, 'number'),
        buttonStyle: 'solid',
        optionType: 'button',
      },
      rules: z.number().default(CommonStatusEnum.ENABLE),
    },
    {
      fieldName: 'targets',
      label: '分发对象',
      component: 'Input',
      formItemClass: 'col-span-2',
      renderComponentContent: () => ({}),
    },
  ];
}

export function usePartyFileSearchSchema(): VbenFormSchema[] {
  return [
    {
      fieldName: 'title',
      label: '标题',
      component: 'Input',
      componentProps: {
        placeholder: '请输入标题',
        allowClear: true,
      },
    },
    {
      fieldName: 'categoryId',
      label: '分类',
      component: 'ApiTreeSelect',
      componentProps: {
        api: async () => handleTree(await getSimplePartyFileCategoryList()),
        labelField: 'name',
        valueField: 'id',
        childrenField: 'children',
        treeDefaultExpandAll: true,
        allowClear: true,
        placeholder: '请选择分类',
      },
    },
    {
      fieldName: 'status',
      label: '状态',
      component: 'Select',
      componentProps: {
        options: getDictOptions(DICT_TYPE.COMMON_STATUS, 'number'),
        allowClear: true,
        placeholder: '请选择状态',
      },
    },
  ];
}

export function usePartyFileColumns(): VxeTableGridOptions<SystemPartyFileApi.PartyFile>['columns'] {
  return [
    { type: 'checkbox', width: 40 },
    { field: 'title', title: '文件标题', minWidth: 220 },
    { field: 'categoryName', title: '分类', minWidth: 140 },
    { field: 'readCount', title: '已读人数', minWidth: 100 },
    { field: 'unreadCount', title: '未读人数', minWidth: 100 },
    {
      field: 'status',
      title: '状态',
      minWidth: 100,
      cellRender: {
        name: 'CellDict',
        props: { type: DICT_TYPE.COMMON_STATUS },
      },
    },
    {
      field: 'publishTime',
      title: '发布时间',
      minWidth: 180,
      formatter: 'formatDateTime',
    },
    {
      title: '操作',
      width: 260,
      fixed: 'right',
      slots: { default: 'actions' },
    },
  ];
}

export function useMyPartyFileSearchSchema(): VbenFormSchema[] {
  return [
    {
      fieldName: 'title',
      label: '标题',
      component: 'Input',
      componentProps: {
        placeholder: '请输入标题',
        allowClear: true,
      },
    },
    {
      fieldName: 'categoryId',
      label: '分类',
      component: 'ApiTreeSelect',
      componentProps: {
        api: async () => handleTree(await getSimplePartyFileCategoryList()),
        labelField: 'name',
        valueField: 'id',
        childrenField: 'children',
        treeDefaultExpandAll: true,
        allowClear: true,
        placeholder: '请选择分类',
      },
    },
    {
      fieldName: 'readStatus',
      label: '阅读状态',
      component: 'Select',
      componentProps: {
        options: [
          { label: '已读', value: true },
          { label: '未读', value: false },
        ],
        allowClear: true,
        placeholder: '请选择阅读状态',
      },
    },
  ];
}

export function useMyPartyFileColumns(): VxeTableGridOptions<SystemPartyFileApi.PartyFile>['columns'] {
  return [
    { field: 'title', title: '文件标题', minWidth: 220 },
    { field: 'categoryName', title: '分类', minWidth: 140 },
    {
      field: 'readStatus',
      title: '阅读状态',
      minWidth: 100,
      formatter: ({ cellValue }) => (cellValue ? '已读' : '未读'),
    },
    {
      field: 'publishTime',
      title: '发布时间',
      minWidth: 180,
      formatter: 'formatDateTime',
    },
    {
      title: '操作',
      width: 160,
      fixed: 'right',
      slots: { default: 'actions' },
    },
  ];
}

export async function buildTargetSelectOptions() {
  const [users, depts, roles] = await Promise.all([
    getSimpleUserList(),
    getSimpleDeptList(),
    getSimpleRoleList(),
  ]);
  return {
    users,
    depts: handleTree(depts),
    roles,
  };
}
